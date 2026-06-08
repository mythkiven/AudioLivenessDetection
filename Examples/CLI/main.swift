import AVFoundation
import AudioLivenessDetection
import Foundation

#if os(macOS)
@main
struct AudioLivenessDemoCLI {
    static func main() {
        runDemo()
        RunLoop.main.run()
    }

    private static func runDemo() {
        print("Audio Liveness Detection — macOS CLI Demo")
        print("Speak into the microphone. Press Ctrl+C to quit.\n")

        let service = AudioLivenessService.shared
        service.onLivenessResult = { report in
            let tag = report.isClassified ? "classified" : "early-exit"
            print(
                "[\(tag)] \(report.result.displayName) | score=\(String(format: "%.3f", report.replayScore)) vr=\(String(format: "%.2f", report.voiceRatio)) ev=\(report.evidenceCount)"
            )
        }
        service.applyDetectionEnabled(true, intervalSec: 10)

        let capture = MicrophoneCapture(sampleRate: 32_000, channels: 1) { pcm in
            service.feedPCM(
                pcm,
                format: PCMFrameFormat(
                    sampleRate: 32_000,
                    channels: 1,
                    bytesPerSample: 2,
                    samples: pcm.count / 2
                )
            )
        }

        do {
            try capture.start()
            print("Microphone started (32kHz mono).\n")
        } catch {
            fputs("Failed to start microphone: \(error)\n", stderr)
            exit(1)
        }
    }
}
#endif

#if os(iOS)
// iOS demo lives in AudioLivenessDemoApp.swift
#endif

/// 跨平台麦克风采集（32kHz mono int16 PCM）
final class MicrophoneCapture {

    private let engine = AVAudioEngine()
    private let sampleRate: Double
    private let channels: AVAudioChannelCount
    private let onPCM: (Data) -> Void

    init(sampleRate: Double, channels: AVAudioChannelCount, onPCM: @escaping (Data) -> Void) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.onPCM = onPCM
    }

    func start() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif

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
