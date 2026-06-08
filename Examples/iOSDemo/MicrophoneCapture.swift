import AVFoundation
import Foundation

#if os(iOS)
/// 麦克风 PCM 采集（转换为 32kHz mono int16 LE）
final class MicrophoneCapture {

    private let engine = AVAudioEngine()
    private let sampleRate: Double
    private let channels: AVAudioChannelCount
    private let onPCM: (Data) -> Void

    init(sampleRate: Double = 32_000, channels: AVAudioChannelCount = 1, onPCM: @escaping (Data) -> Void) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.onPCM = onPCM
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            throw CaptureError.formatUnavailable
        }

        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let converter else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / hwFormat.sampleRate
            )
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: max(frameCapacity, 1)
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
            guard error == nil, converted.frameLength > 0 else { return }

            guard let ptr = converted.int16ChannelData?[0] else { return }
            let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size * Int(self.channels)
            self.onPCM(Data(bytes: ptr, count: byteCount))
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    enum CaptureError: Error {
        case formatUnavailable
    }
}

#endif
