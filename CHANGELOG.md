# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-06-08

### Added

- Swift Package `AudioLivenessDetection` (iOS 13+ / macOS 11+)
- `AudioLivenessService` — PCM feed, lazy start, format adaptation
- `AudioLivenessDetector` — 5 s ring buffer, periodic analysis
- `SimpleVAD` — energy + zero-crossing voice activity detection
- `AudioFeatureExtractor` — FFT 4096, LF/HF/spectral flux features
- Live / Replay / Uncertain classification
- macOS CLI demo (`AudioLivenessDemoCLI`)
- iOS SwiftUI demo (`AudioLivenessDemo`)
- Unit tests for scoring and classification
- [Docs/TECHNICAL.md](Docs/TECHNICAL.md) — full algorithm specification
- Bilingual README ([English](README.md) / [简体中文](README.zh-CN.md))

[1.0.0]: https://github.com/mythkiven/AudioLivenessDetection/releases/tag/v1.0.0
