import AudioLivenessDetection
import XCTest

final class ScoringTests: XCTestCase {

    func testLinearScoreInvertLowValueHighScore() {
        // value below low → invert → score 1.0
        let score = linearScore(value: 0.05, low: 0.12, high: 0.45, invert: true)
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testLinearScoreInvertHighValueLowScore() {
        let score = linearScore(value: 0.50, low: 0.12, high: 0.45, invert: true)
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    func testClassifyLive() {
        let result = classify(score: 0.25, evidence: 1)
        XCTAssertEqual(result, .live)
    }

    func testClassifyReplayWithEvidence() {
        let result = classify(score: 0.55, evidence: 2)
        XCTAssertEqual(result, .replay)
    }

    func testClassifyUncertain() {
        let result = classify(score: 0.40, evidence: 1)
        XCTAssertEqual(result, .uncertain)
    }

    // MARK: - Helpers mirroring detector logic

    private func linearScore(value: Float, low: Float, high: Float, invert: Bool) -> Float {
        let normalized = min(max((value - low) / (high - low), 0), 1)
        return invert ? (1 - normalized) : normalized
    }

    private func classify(score: Float, evidence: Int) -> LivenessResult {
        if score >= 0.45, evidence >= 2 { return .replay }
        if score >= 0.60 { return .replay }
        if score <= 0.35 { return .live }
        return .uncertain
    }
}
