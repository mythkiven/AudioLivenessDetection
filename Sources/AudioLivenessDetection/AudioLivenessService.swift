import Foundation

/// 音频活体检测服务入口（单例可选）
public final class AudioLivenessService {

    public static let shared = AudioLivenessService()

    public var onLivenessResult: ((LivenessDetectionReport) -> Void)?

    public private(set) var isActivated = false

    private var detector: AudioLivenessDetector?
    private var sampleRate = LivenessConstants.defaultSampleRate
    private var channels = LivenessConstants.defaultChannels
    private var checkIntervalMs: Int64 = LivenessConstants.defaultCheckIntervalMs
    private var hasObservedFrameFormat = false

    public init() {}

    /// 开启/关闭检测；`intervalSec` 为分析周期（秒），≤0 时默认 10
    public func applyDetectionEnabled(_ enabled: Bool, intervalSec: Int = 10) {
        let normalizedIntervalMs = Int64((intervalSec > 0 ? intervalSec : 10) * 1000)
        let intervalChanged = checkIntervalMs != normalizedIntervalMs
        checkIntervalMs = normalizedIntervalMs

        if !enabled {
            stopDetection()
            LivenessLogger.log("detection stopped")
            return
        }

        isActivated = true

        if detector != nil {
            if intervalChanged {
                startDetectorIfNeeded()
                LivenessLogger.log(
                    "detection restarted, interval=\(checkIntervalMs)ms sr=\(sampleRate) ch=\(channels)"
                )
            }
            return
        }

        LivenessLogger.log("detection armed, waiting for frame format, interval=\(checkIntervalMs)ms")
    }

    public func stopDetection() {
        isActivated = false
        hasObservedFrameFormat = false
        stopDetectorOnly()
    }

    /// 喂入 PCM（int16 LE）
    public func feedPCM(_ data: Data) {
        feedPCM(
            data,
            format: PCMFrameFormat()
        )
    }

    /// 喂入 PCM 并携带格式；未提供的字段传 0，使用默认值
    public func feedPCM(_ data: Data, format: PCMFrameFormat) {
        guard isActivated, !data.isEmpty else { return }

        let resolvedBPS = format.bytesPerSample > 0
            ? format.bytesPerSample
            : LivenessConstants.defaultBytesPerSample

        if format.bytesPerSample > 0, resolvedBPS != LivenessConstants.defaultBytesPerSample {
            LivenessLogger.log("skip frame: unsupported bytesPerSample=\(format.bytesPerSample)")
            return
        }

        applyFrameFormatIfNeeded(
            sampleRate: format.sampleRate,
            channels: format.channels,
            bytesPerSample: resolvedBPS,
            samples: format.samples,
            frameBytes: data.count
        )

        if detector == nil {
            startDetectorIfNeeded()
        }
        guard let detector else { return }

        guard data.count <= LivenessConstants.maxFeedFrameBytes else { return }
        detector.feedAudioFrame(data)
    }

    public func feedPCM(
        _ audioData: UnsafePointer<UInt8>,
        size: Int,
        format: PCMFrameFormat = PCMFrameFormat()
    ) {
        guard size > 0 else { return }
        feedPCM(Data(bytes: audioData, count: size), format: format)
    }

    // MARK: - Private

    private func applyFrameFormatIfNeeded(
        sampleRate sr: Int,
        channels ch: Int,
        bytesPerSample bps: Int,
        samples: Int,
        frameBytes: Int
    ) {
        let resolvedSR = sr > 0 ? sr : LivenessConstants.defaultSampleRate
        let resolvedCH = ch > 0 ? ch : LivenessConstants.defaultChannels

        if !hasObservedFrameFormat {
            hasObservedFrameFormat = true
            if sr > 0 || ch > 0 {
                LivenessLogger.log(
                    "frame format sr=\(sr) ch=\(ch) bps=\(bps) samples=\(samples) bufLen=\(frameBytes)"
                )
            } else {
                LivenessLogger.log(
                    "frame format unavailable, fallback sr=\(resolvedSR) ch=\(resolvedCH) bufLen=\(frameBytes)"
                )
            }
        }

        guard sampleRate != resolvedSR || channels != resolvedCH else { return }
        sampleRate = resolvedSR
        channels = resolvedCH
        if isActivated {
            startDetectorIfNeeded()
        }
    }

    private func startDetectorIfNeeded() {
        stopDetectorOnly()

        let detector = AudioLivenessDetector(
            sampleRate: sampleRate,
            channels: channels,
            checkIntervalMs: checkIntervalMs
        )
        detector.onResult = { [weak self] report in
            self?.onLivenessResult?(report)
        }
        detector.start()
        self.detector = detector
    }

    private func stopDetectorOnly() {
        detector?.stop()
        detector = nil
    }
}
