# AudioLivenessDetection

端侧 PCM 音频活体检测：区分 **真人实时麦克风** 与 **录音回放**。

纯 Swift 实现，无第三方依赖，适用于 iOS 13+ / macOS 11+。

## 特性

- 基于 VAD + FFT 频谱特征（LF / HF / 谱流变异系数）
- 5 秒滑动缓冲，可配置检测间隔（默认 10 秒）
- 分析在后台队列执行，不阻塞音频回调
- 支持动态采样率 / 声道（默认 32 kHz mono int16 LE）

## 快速开始

### Swift Package Manager

```swift
dependencies: [
    .package(path: "AudioLivenessDetection"), // 或远程 URL
]
```

```swift
import AudioLivenessDetection

let service = AudioLivenessService.shared

service.onLivenessResult = { report in
    print(report.result.displayName, report.replayScore)
}

service.applyDetectionEnabled(true, intervalSec: 10)

// 在音频回调中喂 PCM
service.feedPCM(
    pcmData,
    format: PCMFrameFormat(
        sampleRate: 32_000,
        channels: 1,
        bytesPerSample: 2,
        samples: pcmData.count / 2
    )
)
```

### 直接使用 Detector（无 Service 封装）

```swift
let detector = AudioLivenessDetector()
detector.onResult = { report in /* ... */ }
detector.start()
detector.feedAudioFrame(pcmData)
```

## Demo

### macOS 命令行

```bash
cd AudioLivenessDetection
swift run AudioLivenessDemoCLI
```

对着麦克风说话，终端每 10 秒输出一次检测结果。`Ctrl+C` 退出。

### iOS SwiftUI

1. 用 Xcode 打开 `Package.swift`
2. Scheme 选择 **AudioLivenessDemo**，运行到真机或模拟器
3. 在 Target → Info 中添加：

   | Key | Value |
   |-----|-------|
   | `Privacy - Microphone Usage Description` | Demo needs microphone access |

4. 点击 **Start** 开始检测

## 检测结果

| `LivenessResult` | 含义 |
|------------------|------|
| `.live` | 真人 |
| `.replay` | 录音回放 |
| `.uncertain` | 不确定（人声不足或特征模糊） |

`LivenessDetectionReport.isClassified == false` 表示人声不足等提前退出，此时 `replayScore` 等为 0。

## 项目结构

```
AudioLivenessDetection/
├── Package.swift
├── README.md
├── LICENSE
├── Docs/
│   └── TECHNICAL.md          # 算法与参数完整说明
├── Sources/AudioLivenessDetection/
│   ├── LivenessModels.swift
│   ├── SimpleVAD.swift
│   ├── AudioFeatureExtractor.swift
│   ├── AudioLivenessDetector.swift
│   ├── AudioLivenessService.swift
│   └── LivenessLogger.swift
├── Examples/
│   ├── CLI/                  # macOS 命令行 Demo
│   └── iOSDemo/              # iOS SwiftUI Demo
└── Tests/
```

## 集成要点

| 项 | 说明 |
|----|------|
| PCM 格式 | int16 LE，bytesPerSample = 2 |
| 单帧上限 | Service 侧 ≤ 4096 bytes |
| 未提供格式字段 | 传 `0`，默认 32000 Hz / mono |
| 日志 | `LivenessLogger.isEnabled = true`（默认开启） |

## 技术文档

算法流程、特征公式、阈值常量见 [Docs/TECHNICAL.md](Docs/TECHNICAL.md)。

## 测试

```bash
swift test
```

## License

MIT — 见 [LICENSE](LICENSE)
