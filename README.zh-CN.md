# AudioLivenessDetection

[English](README.md) | **简体中文**

**端侧 PCM 音频活体检测（Swift）—— 区分真人实时麦克风与录音回放。**

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![CI](https://github.com/mythkiven/AudioLivenessDetection/actions/workflows/ci.yml/badge.svg)](https://github.com/mythkiven/AudioLivenessDetection/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/Platform-iOS%2013%2B%20%7C%20macOS%2011%2B-blue.svg)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![SPM](https://img.shields.io/badge/Swift%20PM-compatible-brightgreen.svg)](Package.swift)

> **GitHub：** [mythkiven/AudioLivenessDetection](https://github.com/mythkiven/AudioLivenessDetection)

---

## 这是什么？

**音频活体检测**在设备端分析原始 PCM 音频（无需云端、无需 ASR），输出：

| 结果 | 含义 |
|------|------|
| **Live（真人）** | 符合实时麦克风采集特征 |
| **Replay（回放）** | 更符合预录/外放回放特征 |
| **Uncertain（不确定）** | 人声不足或特征不足以可靠判断 |

适用场景：语音聊天、RTC 应用、反作弊钩子、风控链路。

**关键词：** `音频活体` · `真人/回放` · `PCM` · `VAD` · `FFT` · `端侧检测` · `Swift Package` · `iOS` · `macOS`

---

## 特性

- **端侧运行** — VAD + FFT 频谱特征（LF / HF / 谱流变异系数）
- **轻量** — 纯 Swift，零第三方依赖
- **不阻塞音频线程** — 5 秒环形缓冲，独立后台队列分析
- **灵活输入** — int16 LE PCM，动态采样率/声道（默认 32 kHz mono）
- **自带 Demo** — macOS 命令行 + iOS SwiftUI

---

## 安装（Swift Package Manager）

```swift
dependencies: [
    .package(url: "https://github.com/mythkiven/AudioLivenessDetection.git", from: "1.0.0"),
]
```

本地开发：

```swift
.package(path: "../AudioLivenessDetection")
```

---

## 快速开始

```swift
import AudioLivenessDetection

let service = AudioLivenessService.shared

service.onLivenessResult = { report in
    switch report.result {
    case .live:      print("真人")
    case .replay:    print("回放")
    case .uncertain: print("不确定")
    }
}

service.applyDetectionEnabled(true, intervalSec: 10)

// 在音频回调中喂入 PCM（RTC prep、AVAudioEngine 等）
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

### 底层 API

```swift
let detector = AudioLivenessDetector()
detector.onResult = { report in /* ... */ }
detector.start()
detector.feedAudioFrame(pcmData)
```

---

## Demo

### macOS 命令行

```bash
git clone https://github.com/mythkiven/AudioLivenessDetection.git
cd AudioLivenessDetection
swift run AudioLivenessDemoCLI
```

对着麦克风说话，终端每 10 秒输出一次结果，`Ctrl+C` 退出。

### iOS SwiftUI

1. 用 Xcode 打开 `Package.swift`
2. Scheme 选择 **AudioLivenessDemo**，运行到真机或模拟器
3. Target → Info 添加：**Privacy - Microphone Usage Description**
4. 点击 **Start** 开始检测

---

## 文档

| 文档 | 说明 |
|------|------|
| [README.md](README.md)（English） | 英文说明 |
| [README.zh-CN.md](README.zh-CN.md)（本文件） | 中文说明 |
| [Docs/TECHNICAL.md](Docs/TECHNICAL.md) | 算法、公式与全部阈值 |
| [CHANGELOG.md](CHANGELOG.md) | 版本更新记录 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南 |

---

## 项目结构

```
Sources/AudioLivenessDetection/   # 核心库
Examples/CLI/                     # macOS Demo
Examples/iOSDemo/                 # iOS SwiftUI Demo
Docs/TECHNICAL.md                 # 完整技术规格
Tests/                            # 单元测试
```

---

## 集成要点

| 项 | 说明 |
|----|------|
| PCM 格式 | int16 LE，`bytesPerSample = 2` |
| 单帧上限（Service） | 4096 bytes |
| 未知格式字段 | 传 `0`，默认 32 kHz / mono |
| 日志 | `LivenessLogger.isEnabled`（默认 `true`） |

---

## 测试

```bash
swift test
```

---

## 许可证

MIT — 见 [LICENSE](LICENSE)
