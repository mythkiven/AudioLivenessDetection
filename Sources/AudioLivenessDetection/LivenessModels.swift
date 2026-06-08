import Foundation

/// 活体检测结果
public enum LivenessResult: Int, Sendable {
    case live = 0
    case replay = 1
    case uncertain = 2

    public var displayName: String {
        switch self {
        case .live: return "Live"
        case .replay: return "Replay"
        case .uncertain: return "Uncertain"
        }
    }
}

/// 单次分析报告
public struct LivenessDetectionReport: Sendable {
    public var result: LivenessResult
    public var replayScore: Float
    public var lowFreqRatio: Float
    public var highFreqRatio: Float
    public var frameEnergyCV: Float
    public var spectralFluxCV: Float
    public var spectralCorr: Float
    public var hnr: Float
    public var voiceRatio: Float
    public var evidenceCount: Int
    /// `true` 表示完成特征分析；人声不足等为 `false`
    public var isClassified: Bool

    public init(
        result: LivenessResult = .uncertain,
        replayScore: Float = 0,
        lowFreqRatio: Float = 0,
        highFreqRatio: Float = 0,
        frameEnergyCV: Float = 0,
        spectralFluxCV: Float = 0,
        spectralCorr: Float = 0,
        hnr: Float = 0,
        voiceRatio: Float = 0,
        evidenceCount: Int = 0,
        isClassified: Bool = false
    ) {
        self.result = result
        self.replayScore = replayScore
        self.lowFreqRatio = lowFreqRatio
        self.highFreqRatio = highFreqRatio
        self.frameEnergyCV = frameEnergyCV
        self.spectralFluxCV = spectralFluxCV
        self.spectralCorr = spectralCorr
        self.hnr = hnr
        self.voiceRatio = voiceRatio
        self.evidenceCount = evidenceCount
        self.isClassified = isClassified
    }
}

/// PCM 帧格式描述
public struct PCMFrameFormat: Sendable {
    public var sampleRate: Int
    public var channels: Int
    public var bytesPerSample: Int
    public var samples: Int

    public init(
        sampleRate: Int = 0,
        channels: Int = 0,
        bytesPerSample: Int = 0,
        samples: Int = 0
    ) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bytesPerSample = bytesPerSample
        self.samples = samples
    }
}

/// 默认配置（可用于自定义检测器参数）
public enum AudioLivenessDefaults {
    public static let sampleRate = 32_000
    public static let channels = 1
    public static let checkIntervalMs: Int64 = 10_000
    public static let bufferDurationMs = 5_000
}

struct AudioFeatures {
    var lowFreqEnergyRatio: Float = 0
    var highFreqEnergyRatio: Float = 0
    var frameEnergyCV: Float = 0
    var spectralFluxCV: Float = 0
    var avgSpectralCorrelation: Float = 0
    var harmonicNoiseRatio: Float = 0
    var frameCount: Int = 0
}

struct ScoreResult {
    var score: Float = 0
    var evidenceCount: Int = 0
}

enum LivenessConstants {
    static let defaultSampleRate = 32_000
    static let defaultChannels = 1
    static let defaultBytesPerSample = 2
    static let defaultCheckIntervalMs: Int64 = 10_000
    static let bufferDurationMs = 5_000
    static let vadFrameSize = 4_096
    static let fftSize = 4_096
    static let maxFeedFrameBytes = 4_096

    static let energyFloor: Float = 0.0002
    static let zeroCrossingRateMax: Float = 0.50
    static let strongerChannelRatio: Double = 1.5
    static let minVoiceRatio: Float = 0.05
    static let minVoiceFrames = 2

    static let lfLow: Float = 0.12
    static let lfHigh: Float = 0.45
    static let hfLow: Float = 0.0002
    static let hfHigh: Float = 0.0008
    static let fcvLow: Float = 0.30
    static let fcvHigh: Float = 0.60
    static let lfWeight: Float = 0.45
    static let hfWeight: Float = 0.25
    static let fcvWeight: Float = 0.30
    static let evidenceThreshold: Float = 0.55
    static let replayScoreWithEvidence: Float = 0.45
    static let replayScoreAlone: Float = 0.60
    static let liveScoreMax: Float = 0.35
}
