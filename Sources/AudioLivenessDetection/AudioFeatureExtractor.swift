import Foundation

/// FFT 特征提取（4096 点，Hamming 窗）
final class AudioFeatureExtractor {

    private let fftSize: Int
    private let sampleRate: Int
    private let binWidth: Float
    private let lowFreqMaxBin: Int
    private let highFreqMinBin: Int
    private let halfSpectrum: Int
    private let hammingWindow: [Float]

    init(fftSize: Int = LivenessConstants.fftSize, sampleRate: Int) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.binWidth = Float(sampleRate) / Float(fftSize)
        self.lowFreqMaxBin = Int(300.0 / binWidth)
        self.highFreqMinBin = Int(10_000.0 / binWidth)
        self.halfSpectrum = fftSize / 2
        self.hammingWindow = (0..<fftSize).map { i in
            Float(0.54 - 0.46 * cos(2.0 * Double.pi * Double(i) / Double(fftSize - 1)))
        }
    }

    func extract(from segments: [Data]) -> AudioFeatures {
        var segmentMags: [[[Float]]] = []
        var allMags: [[Float]] = []
        var allFrames: [[Float]] = []

        for segment in segments {
            let samples = segmentToInt16Array(segment)
            let frames = frameWithOverlap(samples: samples)
            var mags: [[Float]] = []
            for frame in frames {
                allFrames.append(frame)
                let mag = fftMagnitude(frame: frame)
                allMags.append(mag)
                mags.append(mag)
            }
            segmentMags.append(mags)
        }

        guard !allFrames.isEmpty else { return AudioFeatures() }

        var features = AudioFeatures()
        features.lowFreqEnergyRatio = computeLowFreqRatio(allMags)
        features.highFreqEnergyRatio = computeHighFreqRatio(allMags)
        features.frameEnergyCV = computeFrameEnergyCV(allMags)
        features.spectralFluxCV = computeSFCV(segmentMags)
        features.avgSpectralCorrelation = computeAvgSpectralCorr(allMags)
        features.harmonicNoiseRatio = computeAverageHNR(allFrames)
        features.frameCount = allFrames.count
        return features
    }

    // MARK: - Features

    private func computeLowFreqRatio(_ magnitudes: [[Float]]) -> Float {
        var lowTotal: Double = 0
        var allTotal: Double = 0
        let maxBin = min(lowFreqMaxBin, halfSpectrum)

        for mag in magnitudes {
            for k in 1...maxBin where k < mag.count {
                let v = mag[k]
                lowTotal += Double(v * v)
            }
            for k in 1...halfSpectrum where k < mag.count {
                let v = mag[k]
                allTotal += Double(v * v)
            }
        }
        return allTotal > 1e-20 ? Float(lowTotal / allTotal) : 0
    }

    private func computeHighFreqRatio(_ magnitudes: [[Float]]) -> Float {
        var highTotal: Double = 0
        var allTotal: Double = 0

        for mag in magnitudes {
            if highFreqMinBin < mag.count {
                for k in highFreqMinBin...halfSpectrum where k < mag.count {
                    let v = mag[k]
                    highTotal += Double(v * v)
                }
            }
            for k in 1...halfSpectrum where k < mag.count {
                let v = mag[k]
                allTotal += Double(v * v)
            }
        }
        return allTotal > 1e-20 ? Float(highTotal / allTotal) : 0
    }

    private func computeFrameEnergyCV(_ magnitudes: [[Float]]) -> Float {
        guard magnitudes.count >= 2 else { return 0 }

        let energies: [Float] = magnitudes.map { mag in
            var e: Double = 0
            for k in 1...halfSpectrum where k < mag.count {
                let v = mag[k]
                e += Double(v * v)
            }
            return Float(e)
        }

        let mean = energies.reduce(0, +) / Float(energies.count)
        guard mean >= 1e-10 else { return 0 }

        let variance = energies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(energies.count)
        return sqrt(variance) / mean
    }

    private func computeSFCV(_ segmentMags: [[[Float]]]) -> Float {
        var allFlux: [Float] = []

        for mags in segmentMags where mags.count >= 2 {
            for i in 1..<mags.count {
                var prevE: Double = 0
                var currE: Double = 0
                for k in 1...halfSpectrum where k < mags[i].count {
                    let pv = mags[i - 1][k]
                    let cv = mags[i][k]
                    prevE += Double(pv * pv)
                    currE += Double(cv * cv)
                }
                let norm = max((prevE + currE) / 2.0, 1e-10)
                var flux: Double = 0
                for k in 1...halfSpectrum where k < mags[i].count {
                    let d = Double(mags[i][k] - mags[i - 1][k])
                    flux += d * d
                }
                allFlux.append(Float(flux / norm))
            }
        }

        guard allFlux.count >= 2 else { return 0 }
        let mean = allFlux.reduce(0, +) / Float(allFlux.count)
        guard mean >= 1e-10 else { return 0 }

        let variance = allFlux.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(allFlux.count)
        return sqrt(variance) / mean
    }

    private func computeAvgSpectralCorr(_ magnitudes: [[Float]]) -> Float {
        guard magnitudes.count >= 3 else { return 0 }

        var avgSpec = [Float](repeating: 0, count: halfSpectrum)
        for mag in magnitudes {
            for k in 0..<halfSpectrum where k + 1 < mag.count {
                avgSpec[k] += mag[k + 1]
            }
        }
        let n = Float(magnitudes.count)
        avgSpec = avgSpec.map { $0 / n }

        let avgMean = avgSpec.reduce(0, +) / Float(halfSpectrum)
        let avgVar = avgSpec.reduce(0) { $0 + ($1 - avgMean) * ($1 - avgMean) } / Float(halfSpectrum)
        let avgStd = max(sqrt(avgVar), 1e-10)

        var totalCorr: Float = 0
        for mag in magnitudes {
            var fMean: Float = 0
            for k in 0..<halfSpectrum where k + 1 < mag.count {
                fMean += mag[k + 1]
            }
            fMean /= Float(halfSpectrum)

            let fVar = (0..<halfSpectrum).reduce(Float(0)) { acc, k in
                guard k + 1 < mag.count else { return acc }
                let d = mag[k + 1] - fMean
                return acc + d * d
            } / Float(halfSpectrum)
            let fStd = max(sqrt(fVar), 1e-10)

            var corr: Float = 0
            for k in 0..<halfSpectrum where k + 1 < mag.count {
                corr += ((mag[k + 1] - fMean) / fStd) * ((avgSpec[k] - avgMean) / avgStd)
            }
            totalCorr += corr / Float(halfSpectrum)
        }
        return totalCorr / Float(magnitudes.count)
    }

    private func computeAverageHNR(_ frames: [[Float]]) -> Float {
        guard !frames.isEmpty else { return 0 }
        let sum = frames.reduce(0.0) { $0 + Double(computeHNR(frame: $1)) }
        return Float(sum / Double(frames.count))
    }

    private func computeHNR(frame: [Float]) -> Double {
        let minLag = sampleRate / 500
        let maxLag = sampleRate / 70
        let frameSize = frame.count
        let effectiveMaxLag = min(maxLag, frameSize - 1)
        guard minLag < effectiveMaxLag else { return 0 }

        var r0: Double = 0
        for s in frame { r0 += Double(s * s) }
        guard r0 >= 1e-10 else { return 0 }

        var maxNormCorr: Double = 0
        for lag in minLag...effectiveMaxLag {
            var rLag: Double = 0
            var lagEnergy: Double = 0
            for i in 0..<(frameSize - lag) {
                let c = Double(frame[i])
                let d = Double(frame[i + lag])
                rLag += c * d
                lagEnergy += d * d
            }
            if lagEnergy > 1e-10 {
                let norm = rLag / sqrt(r0 * lagEnergy)
                if norm > maxNormCorr { maxNormCorr = norm }
            }
        }

        let h = min(max(maxNormCorr, 0), 0.999)
        let denom = max(1.0 - h, 1e-6)
        let hnr = 10.0 * log10(h / denom)
        return min(max(hnr, 0), 30)
    }

    // MARK: - FFT

    private func fftMagnitude(frame: [Float]) -> [Float] {
        var real = [Float](repeating: 0, count: fftSize)
        var imag = [Float](repeating: 0, count: fftSize)
        let len = min(fftSize, frame.count)

        for i in 0..<len {
            real[i] = frame[i] * hammingWindow[i]
        }
        fftReal(&real, &imag, size: fftSize)

        return (0..<fftSize).map { i in
            sqrt(real[i] * real[i] + imag[i] * imag[i])
        }
    }

    private func fftReal(_ real: inout [Float], _ imag: inout [Float], size n: Int) {
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while (j & bit) != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                real.swapAt(i, j)
                imag.swapAt(i, j)
            }
        }

        var len = 2
        while len <= n {
            let half = len / 2
            let ang = Float(-2.0 * Double.pi / Double(len))
            let wR = cos(ang)
            let wI = sin(ang)
            var i = 0
            while i < n {
                var cR: Float = 1
                var cI: Float = 0
                for k in 0..<half {
                    let eI = i + k
                    let oI = eI + half
                    let tR = cR * real[oI] - cI * imag[oI]
                    let tI = cR * imag[oI] + cI * real[oI]
                    real[oI] = real[eI] - tR
                    imag[oI] = imag[eI] - tI
                    real[eI] += tR
                    imag[eI] += tI
                    let nR = cR * wR - cI * wI
                    cI = cR * wI + cI * wR
                    cR = nR
                }
                i += len
            }
            len <<= 1
        }
    }

    private func frameWithOverlap(samples: [Int16]) -> [[Float]] {
        let hop = fftSize / 2
        let int16Max = Float(Int16.max)
        var frames: [[Float]] = []

        guard !samples.isEmpty else { return frames }

        if samples.count < fftSize {
            var frame = [Float](repeating: 0, count: fftSize)
            for i in 0..<fftSize {
                if i < samples.count {
                    frame[i] = Float(samples[i]) / int16Max
                }
            }
            frames.append(frame)
            return frames
        }

        var offset = 0
        while offset + fftSize <= samples.count {
            var frame = [Float](repeating: 0, count: fftSize)
            for i in 0..<fftSize {
                frame[i] = Float(samples[offset + i]) / int16Max
            }
            frames.append(frame)
            offset += hop
        }
        return frames
    }

    private func segmentToInt16Array(_ data: Data) -> [Int16] {
        let count = data.count / MemoryLayout<Int16>.size
        return data.withUnsafeBytes { raw -> [Int16] in
            let ptr = raw.bindMemory(to: Int16.self)
            return Array(ptr.prefix(count))
        }
    }
}
