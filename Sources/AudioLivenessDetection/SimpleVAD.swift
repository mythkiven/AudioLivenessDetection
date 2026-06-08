import Foundation

/// 基于短时能量 + 过零率的简易 VAD
struct SimpleVAD {

    func containsVoice(samples: [Int16]) -> Bool {
        guard !samples.isEmpty else { return false }

        var sumSquared: Double = 0
        var zeroCrossings = 0
        let int16Max = Float(Int16.max)

        for i in 0..<samples.count {
            let normalized = Float(samples[i]) / int16Max
            sumSquared += Double(normalized * normalized)

            if i > 0 {
                let prevSign = samples[i - 1] >= 0
                let currSign = samples[i] >= 0
                if prevSign != currSign {
                    zeroCrossings += 1
                }
            }
        }

        let meanSquaredEnergy = Float(sumSquared / Double(samples.count))
        let zcr = Float(zeroCrossings) / Float(samples.count)
        return meanSquaredEnergy >= LivenessConstants.energyFloor
            && zcr <= LivenessConstants.zeroCrossingRateMax
    }

    func extractMonoChannel(from pcm: Data, channels: Int) -> Data {
        guard pcm.count >= 2 else { return Data() }

        if channels <= 1 {
            return pcm
        }

        let frameSizeBytes = channels * 2
        let frameCount = pcm.count / frameSizeBytes
        guard frameCount > 0 else { return Data() }

        var left = [Int16](repeating: 0, count: frameCount)
        var right = [Int16](repeating: 0, count: frameCount)
        var leftEnergy: Double = 0
        var rightEnergy: Double = 0

        pcm.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<frameCount {
                let offset = i * frameSizeBytes
                let l = readInt16LE(base, offset: offset)
                let r = readInt16LE(base, offset: offset + 2)
                left[i] = l
                right[i] = r
                leftEnergy += Double(l) * Double(l)
                rightEnergy += Double(r) * Double(r)
            }
        }

        let mono: [Int16]
        if leftEnergy > rightEnergy * LivenessConstants.strongerChannelRatio {
            mono = left
        } else if rightEnergy > leftEnergy * LivenessConstants.strongerChannelRatio {
            mono = right
        } else {
            mono = zip(left, right).map { Int16((Int32($0) + Int32($1)) / 2) }
        }

        return mono.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    struct VoiceAnalysis {
        var voiceRatio: Float
        var voiceFrameIndices: [Int]
    }

    func analyzeVoiceFrames(samples: [Int16], frameSize: Int) -> VoiceAnalysis {
        guard !samples.isEmpty, frameSize > 0 else {
            return VoiceAnalysis(voiceRatio: 0, voiceFrameIndices: [])
        }

        if samples.count < frameSize {
            let hasVoice = containsVoice(samples: samples)
            return VoiceAnalysis(
                voiceRatio: hasVoice ? 1 : 0,
                voiceFrameIndices: hasVoice ? [0] : []
            )
        }

        var voiceIndices: [Int] = []
        var totalFrames = 0
        var offset = 0

        while offset + frameSize <= samples.count {
            let slice = Array(samples[offset..<(offset + frameSize)])
            if containsVoice(samples: slice) {
                voiceIndices.append(totalFrames)
            }
            totalFrames += 1
            offset += frameSize
        }

        let ratio = totalFrames > 0 ? Float(voiceIndices.count) / Float(totalFrames) : 0
        return VoiceAnalysis(voiceRatio: ratio, voiceFrameIndices: voiceIndices)
    }

    func extractContinuousSegments(
        samples: [Int16],
        voiceFrameIndices: [Int],
        frameSize: Int
    ) -> [Data] {
        guard !samples.isEmpty, !voiceFrameIndices.isEmpty else { return [] }

        var segments: [Data] = []
        var segStart = voiceFrameIndices[0]
        var segEnd = segStart

        for i in 1..<voiceFrameIndices.count {
            let idx = voiceFrameIndices[i]
            if idx == segEnd + 1 {
                segEnd = idx
            } else {
                appendSegment(
                    samples: samples,
                    segStart: segStart,
                    segEnd: segEnd,
                    frameSize: frameSize,
                    into: &segments
                )
                segStart = idx
                segEnd = idx
            }
        }

        appendSegment(
            samples: samples,
            segStart: segStart,
            segEnd: segEnd,
            frameSize: frameSize,
            into: &segments
        )
        return segments
    }

    private func appendSegment(
        samples: [Int16],
        segStart: Int,
        segEnd: Int,
        frameSize: Int,
        into segments: inout [Data]
    ) {
        let startSample = segStart * frameSize
        let endSample = min((segEnd + 1) * frameSize, samples.count)
        guard endSample > startSample else { return }
        let slice = samples[startSample..<endSample]
        segments.append(slice.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    private func readInt16LE(_ bytes: UnsafePointer<UInt8>, offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
    }
}
