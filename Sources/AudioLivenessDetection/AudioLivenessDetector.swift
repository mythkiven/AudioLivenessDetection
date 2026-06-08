import Foundation

/// 音频活体检测器：环形缓冲 → VAD → 特征 → 打分 → 分类
public final class AudioLivenessDetector {

    public var onResult: ((LivenessDetectionReport) -> Void)?

    private let sampleRate: Int
    private let channels: Int
    private let checkIntervalMs: Int64
    private let frameBytes: Int

    private let vad = SimpleVAD()
    private let featureExtractor: AudioFeatureExtractor
    private var ringBuffer: Data
    private var writePos = 0
    private var bufferFilled = false

    private let bufferQueue = DispatchQueue(label: "audio.liveness.buffer")
    private let analyzeQueue = DispatchQueue(label: "audio.liveness.analyze")
    private var analyzeTimer: DispatchSourceTimer?
    private var started = false

    public init(
        sampleRate: Int = AudioLivenessDefaults.sampleRate,
        channels: Int = AudioLivenessDefaults.channels,
        checkIntervalMs: Int64 = AudioLivenessDefaults.checkIntervalMs,
        bufferDurationMs: Int = AudioLivenessDefaults.bufferDurationMs
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.checkIntervalMs = checkIntervalMs
        self.frameBytes = sampleRate * channels * LivenessConstants.defaultBytesPerSample * bufferDurationMs / 1000
        self.ringBuffer = Data(count: frameBytes)
        self.featureExtractor = AudioFeatureExtractor(sampleRate: sampleRate)
    }

    deinit {
        stop()
    }

    public func start() {
        guard !started else { return }
        started = true

        let timer = DispatchSource.makeTimerSource(queue: analyzeQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(Int(checkIntervalMs)),
            repeating: .milliseconds(Int(checkIntervalMs)),
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            self?.performAnalysis()
        }
        timer.resume()
        analyzeTimer = timer

        LivenessLogger.log("started, interval=\(checkIntervalMs)ms")
    }

    public func stop() {
        guard started else { return }
        started = false
        analyzeTimer?.cancel()
        analyzeTimer = nil
        bufferQueue.sync {
            writePos = 0
            bufferFilled = false
        }
        LivenessLogger.log("stopped")
    }

    public func feedAudioFrame(_ audioData: UnsafePointer<UInt8>, size: Int) {
        guard started, size > 0 else { return }

        bufferQueue.sync {
            let remaining = size
            ringBuffer.withUnsafeMutableBytes { raw in
                guard let buffer = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

                let spaceToEnd = frameBytes - writePos
                if remaining <= spaceToEnd {
                    memcpy(buffer.advanced(by: writePos), audioData, remaining)
                    writePos += remaining
                } else {
                    memcpy(buffer.advanced(by: writePos), audioData, spaceToEnd)
                    let overflow = remaining - spaceToEnd
                    memcpy(buffer, audioData.advanced(by: spaceToEnd), overflow)
                    writePos = overflow
                    bufferFilled = true
                }
                if writePos >= frameBytes {
                    writePos = 0
                    bufferFilled = true
                }
            }
        }
    }

    public func feedAudioFrame(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            feedAudioFrame(base, size: data.count)
        }
    }

    // MARK: - Analysis

    private func performAnalysis() {
        guard let snapshot = snapshotBuffer() else { return }

        let monoData = vad.extractMonoChannel(from: snapshot, channels: channels)
        let monoSamples = monoData.withUnsafeBytes { raw -> [Int16] in
            let ptr = raw.bindMemory(to: Int16.self)
            return Array(ptr)
        }

        let voiceInfo = vad.analyzeVoiceFrames(
            samples: monoSamples,
            frameSize: LivenessConstants.vadFrameSize
        )

        LivenessLogger.log(
            "buffer: \(monoSamples.count) samples, voiceRatio=\(String(format: "%.3f", voiceInfo.voiceRatio)), voiceFrames=\(voiceInfo.voiceFrameIndices.count)"
        )

        if voiceInfo.voiceRatio < LivenessConstants.minVoiceRatio
            || voiceInfo.voiceFrameIndices.count < LivenessConstants.minVoiceFrames {
            deliverReport(uncertainReport(voiceRatio: voiceInfo.voiceRatio, hnr: 0), classified: false)
            LivenessLogger.log("skip: insufficient voice")
            return
        }

        let segments = vad.extractContinuousSegments(
            samples: monoSamples,
            voiceFrameIndices: voiceInfo.voiceFrameIndices,
            frameSize: LivenessConstants.vadFrameSize
        )
        let features = featureExtractor.extract(from: segments)

        if features.frameCount < 2 {
            deliverReport(
                uncertainReport(voiceRatio: voiceInfo.voiceRatio, hnr: features.harmonicNoiseRatio),
                classified: false
            )
            LivenessLogger.log("skip: too few FFT frames (\(features.frameCount))")
            return
        }

        let scoreResult = computeReplayScore(features: features)
        let result = classifyResult(scoreResult)

        var report = LivenessDetectionReport()
        report.result = result
        report.replayScore = scoreResult.score
        report.lowFreqRatio = features.lowFreqEnergyRatio
        report.highFreqRatio = features.highFreqEnergyRatio
        report.frameEnergyCV = features.frameEnergyCV
        report.spectralFluxCV = features.spectralFluxCV
        report.spectralCorr = features.avgSpectralCorrelation
        report.hnr = features.harmonicNoiseRatio
        report.voiceRatio = voiceInfo.voiceRatio
        report.evidenceCount = scoreResult.evidenceCount

        LivenessLogger.log(
            "【\(result.rawValue)】score=\(String(format: "%.3f", scoreResult.score)) ev=\(scoreResult.evidenceCount) | LF=\(String(format: "%.4f", features.lowFreqEnergyRatio)) HF=\(String(format: "%.5f", features.highFreqEnergyRatio)) eCV=\(String(format: "%.3f", features.frameEnergyCV)) fCV=\(String(format: "%.3f", features.spectralFluxCV)) SC=\(String(format: "%.3f", features.avgSpectralCorrelation)) HNR=\(String(format: "%.1f", features.harmonicNoiseRatio)) vr=\(String(format: "%.2f", voiceInfo.voiceRatio)) frames=\(features.frameCount)"
        )

        deliverReport(report, classified: true)
    }

    private func snapshotBuffer() -> Data? {
        bufferQueue.sync {
            if !bufferFilled && writePos < frameBytes / 2 {
                return nil
            }
            let usableSize = bufferFilled ? frameBytes : writePos
            guard usableSize > 0 else { return nil }

            var out = Data(count: usableSize)
            ringBuffer.withUnsafeBytes { srcRaw in
                out.withUnsafeMutableBytes { dstRaw in
                    guard
                        let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    else { return }

                    if bufferFilled {
                        let tailLen = frameBytes - writePos
                        memcpy(dst, src.advanced(by: writePos), tailLen)
                        memcpy(dst.advanced(by: tailLen), src, writePos)
                    } else {
                        memcpy(dst, src, writePos)
                    }
                }
            }
            return out
        }
    }

    private func uncertainReport(voiceRatio: Float, hnr: Float) -> LivenessDetectionReport {
        var report = LivenessDetectionReport()
        report.result = .uncertain
        report.hnr = hnr
        report.voiceRatio = voiceRatio
        return report
    }

    private func deliverReport(_ report: LivenessDetectionReport, classified: Bool) {
        var delivered = report
        delivered.isClassified = classified
        onResult?(delivered)
    }

    private func linearScore(value: Float, low: Float, high: Float, invert: Bool) -> Float {
        let normalized = min(max((value - low) / (high - low), 0), 1)
        return invert ? (1 - normalized) : normalized
    }

    private func computeReplayScore(features: AudioFeatures) -> ScoreResult {
        let lfScore = linearScore(
            value: features.lowFreqEnergyRatio,
            low: LivenessConstants.lfLow,
            high: LivenessConstants.lfHigh,
            invert: true
        )
        let hfScore = linearScore(
            value: features.highFreqEnergyRatio,
            low: LivenessConstants.hfLow,
            high: LivenessConstants.hfHigh,
            invert: true
        )
        let fcvScore = linearScore(
            value: features.spectralFluxCV,
            low: LivenessConstants.fcvLow,
            high: LivenessConstants.fcvHigh,
            invert: true
        )

        LivenessLogger.log(
            "scores: lf=\(String(format: "%.2f", lfScore)) hf=\(String(format: "%.2f", hfScore)) fcv=\(String(format: "%.2f", fcvScore))"
        )

        let rawScore = min(
            max(
                lfScore * LivenessConstants.lfWeight
                    + hfScore * LivenessConstants.hfWeight
                    + fcvScore * LivenessConstants.fcvWeight,
                0
            ),
            1
        )

        var evidenceCount = 0
        if lfScore >= LivenessConstants.evidenceThreshold { evidenceCount += 1 }
        if hfScore >= LivenessConstants.evidenceThreshold { evidenceCount += 1 }
        if fcvScore >= LivenessConstants.evidenceThreshold { evidenceCount += 1 }

        return ScoreResult(score: rawScore, evidenceCount: evidenceCount)
    }

    private func classifyResult(_ score: ScoreResult) -> LivenessResult {
        if score.score >= LivenessConstants.replayScoreWithEvidence
            && score.evidenceCount >= 2 {
            return .replay
        }
        if score.score >= LivenessConstants.replayScoreAlone {
            return .replay
        }
        if score.score <= LivenessConstants.liveScoreMax {
            return .live
        }
        return .uncertain
    }
}
