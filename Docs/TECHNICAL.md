# 音频活体检测（Audio Liveness Detection）技术文档

> **Swift 开源实现**：本目录 `Sources/AudioLivenessDetection/`  
> **API 映射**：`BXORAudioLivenessService` → `AudioLivenessService`，`BXORAudioLivenessDetector` → `AudioLivenessDetector`

---

## 1. 能力说明

端侧 PCM 音频活体检测：周期性分析麦克风音频流，区分 **真人实时采集** 与 **录音回放**。

| 结果 | 含义 |
|------|------|
| **Live** | 符合真人实时麦克风特征 |
| **Replay** | 更符合录音回放特征 |
| **Uncertain** | 人声不足或特征不足以可靠判断 |

**特点**：

- 纯端侧，基于 PCM 频谱与时域特征，不依赖 ASR
- 固定 5s 滑动缓冲 + 可配置检测间隔（默认 10s）
- 分析在独立后台队列执行，不阻塞音频回调线程

---

## 2. 音频输入规范

### 2.1 PCM 格式

| 参数 | 要求 | 典型值 |
|------|------|--------|
| 编码 | **PCM int16 LE**（小端 16bit 有符号） | — |
| 采样率 | 动态传入；未提供时默认 **32000 Hz** | 32000 |
| 声道 | 动态传入；未提供时默认 **1（mono）** | 1 |
| 每采样字节 | **2**；非 2 字节的帧会被丢弃 | 2 |
| 单帧大小 | 无固定要求，由 RTC/SDK 决定 | 640 bytes（320 samples × 2，32k/mono） |

立体声输入时，算法内部会转为 mono（见 §4.3）。

### 2.5 feedPCM 边界条件

| 条件 | 行为 |
|------|------|
| `!isActivated` | 直接丢弃，不写入缓冲 |
| `audioData == NULL` 或 `size <= 0` | 丢弃 |
| `bytesPerSample > 0` 且 ≠ 2 | 丢弃，打日志 `skip frame: unsupported bytesPerSample` |
| `intervalSec <= 0` | 归一化为 **10s** |
| 单帧 `size > 4096`（参考实现） | **不喂入**（`kBXORLivenessFrameScratchMax`） |
| Prep 参考实现 | 必须先 `memcpy` 到栈上 scratch 再 feed，避免 inFrame 被后续链路改写 |

**`isActivated`**：仅 `applyLivenessDetectionEnabled:YES` 时为 YES；Prep 侧应检查此标志再 feed，避免无效拷贝。

### 2.2 喂入接口

通过 `BXORAudioLivenessService` 单例喂入每帧 PCM：

```objc
// 简化版（格式字段传 0，使用默认值 32000/mono/2）
- (void)feedPCM:(const unsigned char *)audioData size:(int)size;

// 推荐：携带 RTC 真实格式
- (void)feedPCM:(const unsigned char *)audioData
           size:(int)size
     sampleRate:(int)sampleRate
       channels:(int)channels
 bytesPerSample:(int)bytesPerSample
        samples:(int)samples;
```

**格式字段约定**：SDK 无法提供的字段传 **`0`**，Service 用默认值兜底（32000 / 1 / 2）。

### 2.3 接入位置（iOS 参考实现）

在 RTC **Audio Prep** 回调中取 PCM，与实际上行音频路径一致：

```
RTC 麦克风帧
    → [可选] 音频前处理（变声/音效等）
    → Audio Prep Proxy：复制 inFrame → feedPCM
    → 继续上行
```

iOS 参考接入点：`BXORBiggieMicAudioProxy`，注册在 prep 链中，每帧将 `inFrame` 复制后送入 Service。

Prep 协议扩展（`YppAudioPrepProtocol`）optional 回调示例：

```objc
- (void)audioPreprocessWithInFrame:(unsigned char *)inFrame
                          outFrame:(unsigned char *)outFrame
                            length:(int)inFrameLength
                        sampleRate:(int)sampleRate
                          channels:(int)channels
                   bytesPerSample:(int)bytesPerSample
                         samples:(int)samples;
```

各 RTC SDK 透传情况（`sonaaudio`）：

| SDK | sampleRate / channels | bytesPerSample / samples |
|-----|----------------------|--------------------------|
| Zego | 透传 | 透传 |
| TRTC | 透传 | 传 `0`（SDK 无此字段） |
| Agora | 透传 | 透传 |

### 2.4 启停与格式自适应

```objc
// 开启检测；intervalSec 为分析周期（秒），默认 10
- (void)applyLivenessDetectionEnabled:(BOOL)enabled intervalSec:(NSInteger)intervalSec;

// 停止检测
- (void)stopLivenessDetection;

// 读取结果（每次分析周期结束回调一次）
@property (nonatomic, copy) void (^onLivenessResult)(BXORAudioLivenessDetectionReport *report);
```

**Service 内部逻辑**：

1. `enabled=true` → `isActivated=YES`，等待首帧 PCM（lazy start）
2. 首帧到达 → 解析 sampleRate/channels → 创建 Detector 并 start
3. sampleRate 或 channels 变化 → 重建 Detector
4. `intervalSec` 变化 → 重建 Detector
5. `enabled=false` → 停止并释放 Detector

**补充**：

- `enabled=true` 且 Detector 已存在、**interval 未变** → 不重建，直接 return
- `stopLivenessDetection` 会重置 `hasObservedFrameFormat`，下次 enable 重新打格式日志

---

## 3. 模块架构

```
┌──────────────────────────────────────────────────────────────┐
│  BXORAudioLivenessService（单例）                             │
│  · 启停控制、格式解析、PCM 转发                                │
└──────────────────────────┬───────────────────────────────────┘
                           │ feedAudioFrame
┌──────────────────────────▼───────────────────────────────────┐
│  BXORAudioLivenessDetector                                   │
│  · 5s 环形缓冲 → 定时分析 → 打分 → 分类                        │
│  ├─ BXORSimpleVAD          （人声检测 / mono 提取 / 段切分）   │
│  └─ BXORAudioFeatureExtractor （FFT 4096 + 6 项特征）          │
└──────────────────────────────────────────────────────────────┘
```

### 3.1 线程模型

| 组件 | 线程/队列 |
|------|-----------|
| `feedPCM` | 音频回调线程（同步写 ring buffer） |
| `bufferQueue` | 串行队列，PCM 写入与 snapshot |
| `analyzeQueue` | 串行队列，定时器触发分析 |
| `onLivenessResult` | 在 analyzeQueue 上回调 |

**集成注意**：`feedPCM` 内对 ring buffer 的写操作为 `dispatch_sync`，需保证单帧 feed 耗时极短；分析逻辑全部在 analyzeQueue。

### 3.2 检测结果结构

```objc
typedef NS_ENUM(NSInteger, BXORAudioLivenessResult) {
    BXORAudioLivenessResultLive = 0,      // 真人
    BXORAudioLivenessResultReplay,        // 回放
    BXORAudioLivenessResultUncertain,     // 不确定
};

@interface BXORAudioLivenessDetectionReport : NSObject
@property BXORAudioLivenessResult result;  // Live / Replay / Uncertain
@property float replayScore;          // 回放综合分 [0, 1]
@property float lowFreqRatio;         // LF
@property float highFreqRatio;        // HF
@property float frameEnergyCV;        // eCV
@property float spectralFluxCV;       // fCV
@property float spectralCorr;         // SC（仅日志，不参与打分）
@property float hnr;                  // HNR（仅日志，不参与打分）
@property float voiceRatio;           // 人声占比
@property int evidenceCount;          // 回放证据条数
@property BOOL isClassified;          // YES=完成特征分析；NO=人声不足等提前退出
@end
```

### 3.3 回调语义（重要）

定时器每周期触发 `performAnalysis`，但**并非每次都回调**：

| 情况 | 是否回调 | `result` | `isClassified` | 说明 |
|------|----------|----------|----------------|------|
| 缓冲未满半且未 wrap | **否** | — | — | `snapshotBuffer` 返回 nil，静默跳过 |
| 人声不足（§4.3） | 是 | Uncertain | **NO** | `replayScore=0`，LF/HF/eCV/fCV/SC=0，`hnr=0` |
| FFT 帧 < 2 | 是 | Uncertain | **NO** | 保留 `voiceRatio` 和 `hnr` |
| 正常分类 | 是 | Live/Replay/Uncertain | **YES** | 全部特征字段有效 |

回调链：`Detector.onResult` → `Service.onLivenessResult`（均在 analyzeQueue）。

---

## 4. 检测算法

### 4.1 流程

```
每帧 PCM ──→ 写入 5s 环形缓冲
                │
     每 checkIntervalMs（默认 10s）触发
                │
                ▼
         snapshot 最近 5s PCM
                │
                ▼
         立体声 → mono
                │
                ▼
         VAD（4096 samples/帧）→ voiceRatio
                │
      voiceRatio < 0.05 或 voice 帧 < 2
                │
         ┌──────┴──────┐
         ▼             ▼
    Uncertain      提取连续人声段
                         │
                         ▼
                  FFT 特征（4096, 50% overlap）
                         │
                         ▼
                  replayScore + evidenceCount
                         │
                         ▼
                  Live / Replay / Uncertain
```

### 4.2 环形缓冲

| 参数 | 值 |
|------|-----|
| `bufferDurationMs` | **5000**（固定） |
| `frameBytes` | `sampleRate × channels × 2 × 5` |
| 32k/mono 示例 | 320000 bytes = 160000 samples |
| 最小可分析量 | buffer 半满（`writePos >= frameBytes/2`）或已 wrap，否则**本轮无回调** |

**存储格式**：原始 interleaved PCM（立体声为 LRLR…），mono 转换在 snapshot 之后分析阶段进行。

**写入**：环形覆盖；`writePos` 到达 `frameBytes` 时归零并置 `bufferFilled=YES`。

**snapshot**：若已 wrap，按时间序从 `writePos` 起拼接 `[tail..end] + [0..writePos)`；未 wrap 则取 `[0..writePos)`。

### 4.2.1 定时器

| 参数 | 值 |
|------|-----|
| 类型 | `DISPATCH_SOURCE_TYPE_TIMER`，跑在 analyzeQueue |
| 首次触发 | `start` 后 **checkIntervalMs**（非立即） |
| 周期 | checkIntervalMs（默认 10000ms） |
| leeway | 100ms |
| 异常 | `@try/@catch` 包裹分析，异常打日志不崩溃 |

### 4.3 VAD（BXORSimpleVAD）

每 **4096 samples** 判定是否含人声：

| 参数 | 值 |
|------|-----|
| `kEnergyFloor` | `0.0002`（归一化均方能量） |
| `kZeroCrossingRateMax` | `0.50` |
| `kStrongerRatio` | `1.5`（立体声选声道阈值） |
| 人声帧判定 | `energy >= floor && ZCR <= max` |

**能量与过零率**（样本先归一化 `s = sample / INT16_MAX`）：

```
meanSquaredEnergy = sum(s²) / count
ZCR = zeroCrossings / count    // 相邻样本符号变化计数
```

**短缓冲**（总 samples < 4096）：只做一次判定，`voiceRatio` 为 0 或 1。

**立体声 interleaved LE**：逐帧读 int16，`frameSizeBytes = channels × 2`。

**连续人声段**：按 VAD 帧索引连续性分组（索引差 > 1 则切段），每段单独做 FFT。

**前置过滤**（不满足 → Uncertain，跳过特征分析）：

| 条件 | 阈值 |
|------|------|
| `voiceRatio` | `< 0.05` |
| 人声帧数 | `< 2` |

`voiceRatio = 人声帧数 / 总 VAD 帧数`

**立体声转 mono**：

- 左/右能量比 > **1.5** → 取能量较大声道
- 否则 → 左右平均

### 4.4 特征提取（BXORAudioFeatureExtractor）

| 参数 | 值 |
|------|-----|
| FFT Size | **4096** |
| 窗函数 | Hamming：`0.54 - 0.46 × cos(2πi/(N-1))` |
| Hop Size | **2048**（50% overlap） |
| 低频带 | **0 ~ 300 Hz** |
| 高频带 | **≥ 10000 Hz**（至 Nyquist） |
| FFT 实现 | 自实现 radix-2 Cooley-Tukey（非 Accelerate/vDSP） |

**Bin 计算**（随 sampleRate 动态变化）：

```
binWidth       = sampleRate / fftSize
lowFreqMaxBin  = floor(300 / binWidth)
highFreqMinBin = floor(10000 / binWidth)
halfSpectrum   = fftSize / 2
```

**样本归一化**：`(float)sample / INT16_MAX` → [-1, 1]。

**短段**（samples < fftSize）：零填充至 4096，只产生 1 个 FFT 帧。

**谱幅度**：Hamming 加窗 → FFT → `mag[k] = sqrt(re² + im²)`，数组长度 fftSize；能量求和时 **k 从 1 到 halfSpectrum**（跳过 DC）。

| 特征 | 字段 | 计算公式 | 参与打分 |
|------|------|----------|----------|
| 低频能量比 | LF | `sum(mag[1..lowBin]²) / sum(mag[1..half]²)` | ✅ |
| 高频能量比 | HF | `sum(mag[highBin..half]²) / sum(mag[1..half]²)` | ✅ |
| 帧能量 CV | eCV | 各帧总能量（mag² 求和）的 `std/mean` | ❌ |
| 谱流 CV | fCV | 见下 | ✅ |
| 平均谱相关 | SC | 各帧与均谱 Pearson 相关的均值（需 ≥3 帧） | ❌ |
| 谐噪比 | HNR | 见下 | ❌ |

**谱流**（段内相邻 FFT 帧）：

```
flux[i] = sum((mag[i,k] - mag[i-1,k])²) / max((E[i-1]+E[i])/2, 1e-10)
fCV = std(flux) / mean(flux)
```

**HNR**（每 FFT 帧，lag ∈ `[sr/500, sr/70]`，即约 500Hz~70Hz 基频搜索）：

```
h = max normalized autocorrelation(lag), clamp to [0, 0.999]
HNR = clamp(10 × log10(h / (1-h)), 0, 30) dB
```

FFT 有效帧数 < 2 → Uncertain（`isClassified=NO`）。

### 4.5 回放打分

子分数通过 `linearScoreWithValue(value, low, high, invert=true)` 计算（**值越低，子分越高**）：

```
normalized = clamp((value - low) / (high - low), 0, 1)
score      = invert ? (1 - normalized) : normalized
```

| 子分 | 特征 | low | high | 权重 |
|------|------|-----|------|------|
| `lfScore` | LF | 0.12 | 0.45 | **0.45** |
| `hfScore` | HF | 0.0002 | 0.0008 | **0.25** |
| `fcvScore` | fCV | 0.30 | 0.60 | **0.30** |

> 设计思路：录音回放常经扬声器播放，高频物理带宽受限 → LF 偏高、HF 偏低、谱流变化小（fCV 偏低）→ 子分升高。`voiceRatio` 传入但未参与打分。

```
rawScore = clamp(lfScore×0.45 + hfScore×0.25 + fcvScore×0.30, 0, 1)
```

证据计数（子分 ≥ **0.55** 各计 1）：

```
evidenceCount = count(lfScore≥0.55) + count(hfScore≥0.55) + count(fcvScore≥0.55)
```

### 4.6 分类规则

| 条件 | 结果 |
|------|------|
| `score ≥ 0.45` 且 `evidenceCount ≥ 2` | **Replay** |
| `score ≥ 0.60` | **Replay** |
| `score ≤ 0.35` | **Live** |
| 其他 | **Uncertain** |

---

## 5. 参数速查表

### 5.1 运行时参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| 检测间隔 | 10s | `applyLivenessDetectionEnabled:intervalSec:` |
| 分析缓冲时长 | 5s | 固定 |
| 默认采样率 | 32000 | RTC 首帧可覆盖 |
| 默认声道 | 1 | RTC 首帧可覆盖 |

### 5.2 算法常量

| 模块 | 常量 | 值 |
|------|------|-----|
| VAD | frameSize | 4096 samples |
| VAD | energyFloor | 0.0002 |
| VAD | zcrMax | 0.50 |
| VAD | min voiceRatio | 0.05 |
| VAD | min voice frames | 2 |
| FFT | size / hop | 4096 / 2048 |
| 频带 | low / high | 0–300 Hz / ≥10000 Hz |
| 打分 | LF / HF / fCV range | 0.12–0.45 / 0.0002–0.0008 / 0.30–0.60 |
| 打分 | 权重 | LF 0.45, HF 0.25, fCV 0.30 |
| 打分 | evidence 阈值 | 0.55 |
| 分类 | replay | score≥0.45 & ev≥2，或 score≥0.60 |
| 分类 | live | score≤0.35 |
| 分类 | uncertain | 其余 |

### 5.3 其他常量

| 常量 | 值 |
|------|-----|
| Prep 单帧上限 | 4096 bytes |
| 定时器 leeway | 100ms |
| HNR 输出范围 | [0, 30] dB |
| 能量/EPS 防零 | 1e-10 ~ 1e-20 |

---

## 6. 源码文件

| 文件 | 职责 |
|------|------|
| `BXORSimpleVAD.m/h` | VAD、mono 提取、人声段切分 |
| `BXORAudioFeatureExtractor.m/h` | FFT + 特征计算 |
| `BXORAudioLivenessDetector.m/h` | 环形缓冲、定时分析、打分分类 |
| `BXORAudioLivenessService.m/h` | 单例、启停、PCM 入口、结果回调 |
| `BXORBiggieMicAudioProxy.mm` | iOS Prep 链接入参考实现 |

**外部依赖（iOS Prep 透传格式）**：`yppaudioprep`、`sonaaudio`

---

## 7. 集成指南

### 7.1 最小集成步骤

1. 拷贝 §6 中 4 个核心算法文件（VAD / FeatureExtractor / Detector / Service）
2. 在音频回调中每帧调用 `feedPCM`（推荐带 sampleRate/channels）
3. 设置 `onLivenessResult` 接收周期性结果
4. 在合适的生命周期调用 `applyLivenessDetectionEnabled:intervalSec:` / `stopLivenessDetection`

### 7.2 检查清单

- [ ] PCM 为 int16 LE，bytesPerSample = 2
- [ ] 音频回调线程不执行 FFT/分析（仅 feed）
- [ ] 采样率变化时能重建 Detector（Service 已内置）
- [ ] ring buffer 写入与 prep 回调同线程，保持 thread-safe
- [ ] 日志 tag：`[BXOR][Liveness]`

### 7.3 日志示例

```
[BXOR][Liveness] rtc frame format sr=32000 ch=1 bps=2 samples=320 bufLen=640
[BXOR][Liveness] started, interval=10000ms
[BXOR][Liveness] buffer: 160000 samples, voiceRatio=0.308, voiceFrames=12
[BXOR][Liveness] scores: lf=0.00 hf=1.00 fcv=0.00
[BXOR][Liveness] 【0】score=0.250 ev=1 | LF=0.7391 HF=0.00000 eCV=0.450 fCV=0.889 SC=0.770 HNR=10.6 vr=0.31 frames=21
```

`【0】`= Live，`【1】`= Replay，`【2】`= Uncertain。

### 7.4 已知场景

| 场景 | 现象 | 说明 |
|------|------|------|
| 长时间静音 | voiceRatio=0，Uncertain | 人声不足；仍回调，`isClassified=NO` |
| 刚启动前 5s | 可能无回调 | 缓冲未满半且未 wrap 时静默跳过 |
| 耳机 / 蓝牙麦 | HF 偏低，结果波动 | 高频衰减导致 hfScore 偏高 |
| 32k vs 48k | HF 比值差异 | FFT bin 按 sampleRate 动态计算，Nyquist 不同 |
| TRTC | bytesPerSample/samples=0 | 默认值兜底 |

---

## 8. 验证方法

**真人**：持续说话 ≥10s，期望 `voiceRatio > 0.05`，多数周期结果为 Live。

**回放**：外放预录人声由麦克风采集，期望结果为 Replay，关注 `ev ≥ 2`。

**关闭**：调用 `applyLivenessDetectionEnabled:NO`，期望无周期分析日志。

---

## 9. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-06 | 首版落地 |

阈值调整请同步更新 §4.5 / §5.2 及源码常量。

---

## 10. 文档 vs 源码：还原度说明

| 维度 | 能否仅凭文档还原 | 说明 |
|------|------------------|------|
| 模块分层 / 数据流 | ✅ 可以 | §2–§3 已覆盖 |
| VAD / 打分 / 分类阈值 | ✅ 可以 | §4.3–§4.6、§5.2 参数完整 |
| 特征计算公式 | ✅ 可以 | §4.4 已补公式与 bin 计算 |
| FFT 实现 | ⚠️ 有偏差风险 | 文档注明自实现 Cooley-Tukey；换 vDSP/FFTW 数值可能微差，逻辑等价即可 |
| 回调时机 | ✅ 可以 | §3.3 已区分「无回调 / Uncertain / 正常」三种路径 |
| iOS Prep 接入细节 | ✅ 可以 | §2.3–§2.5 含 scratch 拷贝与 4096 上限 |

**建议**：其他团队优先 **直接拷贝 §6 源码** 再按 §7 接入；若跨语言重写，以 §4.4 公式 + §5.2 常量为准自测对齐日志。
