# AudioLivenessDetection

**English** | [简体中文](README.zh-CN.md)

**On-device PCM audio liveness detection for Swift — classify live microphone speech vs recorded replay.**

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![CI](https://github.com/mythkiven/AudioLivenessDetection/actions/workflows/ci.yml/badge.svg)](https://github.com/mythkiven/AudioLivenessDetection/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/Platform-iOS%2013%2B%20%7C%20macOS%2011%2B-blue.svg)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![SPM](https://img.shields.io/badge/Swift%20PM-compatible-brightgreen.svg)](Package.swift)

> **GitHub:** [mythkiven/AudioLivenessDetection](https://github.com/mythkiven/AudioLivenessDetection)

---

## What is this?

**Audio liveness detection** analyzes raw PCM audio on the device (no cloud, no ASR) and returns:

| Result | Meaning |
|--------|---------|
| **Live** | Real-time microphone capture |
| **Replay** | Likely pre-recorded / played-back audio |
| **Uncertain** | Not enough voice or ambiguous features |

Use cases: voice chat, RTC apps, anti-spoofing hooks, risk control pipelines.

**Keywords:** `audio liveness` · `live vs replay` · `PCM` · `VAD` · `FFT` · `on-device` · `Swift Package` · `iOS` · `macOS` · `voice activity detection`

---

## Features

- **On-device** — VAD + FFT spectral features (LF / HF / spectral flux CV)
- **Lightweight** — pure Swift, zero third-party dependencies
- **Non-blocking** — 5 s ring buffer, analysis on a background queue
- **Flexible input** — int16 LE PCM, dynamic sample rate / channels (default 32 kHz mono)
- **Demos included** — macOS CLI + iOS SwiftUI

---

## Installation (Swift Package Manager)

```swift
dependencies: [
    .package(url: "https://github.com/mythkiven/AudioLivenessDetection.git", from: "1.0.0"),
]
```

Or local path during development:

```swift
.package(path: "../AudioLivenessDetection")
```

---

## Quick Start

```swift
import AudioLivenessDetection

let service = AudioLivenessService.shared

service.onLivenessResult = { report in
    switch report.result {
    case .live:      print("Live")
    case .replay:    print("Replay")
    case .uncertain: print("Uncertain")
    }
}

service.applyDetectionEnabled(true, intervalSec: 10)

// Feed PCM from your audio callback (RTC prep, AVAudioEngine, etc.)
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

### Lower-level API

```swift
let detector = AudioLivenessDetector()
detector.onResult = { report in /* ... */ }
detector.start()
detector.feedAudioFrame(pcmData)
```

---

## Demo

### macOS CLI

```bash
git clone https://github.com/mythkiven/AudioLivenessDetection.git
cd AudioLivenessDetection
swift run AudioLivenessDemoCLI
```

Speak into the mic — results print every 10 seconds. `Ctrl+C` to quit.

### iOS SwiftUI

1. Open `Package.swift` in Xcode
2. Select scheme **AudioLivenessDemo** → run on device or simulator
3. Add to target Info: **Privacy - Microphone Usage Description**
4. Tap **Start**

---

## Documentation

| Doc | Audience |
|-----|----------|
| [README.md](README.md) (English) | Overview, install, demo |
| [README.zh-CN.md](README.zh-CN.md) (简体中文) | 中文说明 |
| [Docs/TECHNICAL.md](Docs/TECHNICAL.md) | Algorithm, formulas, all thresholds |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |

---

## Project Layout

```
Sources/AudioLivenessDetection/   # Library
Examples/CLI/                     # macOS demo
Examples/iOSDemo/                 # iOS SwiftUI demo
Docs/TECHNICAL.md                 # Full technical spec
Tests/                            # Unit tests
```

---

## Integration Notes

| Item | Value |
|------|-------|
| PCM | int16 LE, `bytesPerSample = 2` |
| Max frame size (Service) | 4096 bytes |
| Unknown format fields | pass `0` → defaults to 32 kHz / mono |
| Logging | `LivenessLogger.isEnabled` (default `true`) |

---

## Test

```bash
swift test
```

---

## License

MIT — see [LICENSE](LICENSE)
