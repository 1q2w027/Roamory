import XCTest
@testable import RoamoryKit

final class LocalScorerTests: XCTestCase {
    let config = try! DetectionConfig.bundled()

    func signals(change: Double, sharpness: Double = 0, clipped: Double = 0, dhash: UInt64 = 0) -> FrameSignals {
        FrameSignals(sharpness: sharpness, meanLuma: 128, clippedFraction: clipped, change: change, dhash: dhash)
    }

    func testTrdFormula() {
        var scorer = LocalScorer(config: config)
        for _ in 0..<5 { _ = scorer.score(signals(change: 5), dwell: 0, recentEscalated: []) }
        let r = scorer.score(signals(change: 15, sharpness: 100, clipped: 0.2, dhash: 0), dwell: 1,
                             recentEscalated: [0x0000_0000_0000_FFFF])  // 16 bits away
        XCTAssertEqual(r.changeSpike, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.quality, 0.4, accuracy: 1e-9)
        XCTAssertEqual(r.novelty, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.l, 0.63, accuracy: 1e-9)
    }

    func testNoveltyIsFullWithNoRecentEscalations() {
        var scorer = LocalScorer(config: config)
        XCTAssertEqual(scorer.score(signals(change: 0), dwell: 0, recentEscalated: []).novelty, 1)
    }

    func testBlackFramesScoreFiniteAndLow() {
        var scorer = LocalScorer(config: config)
        let black = FrameSignals.compute(.solid(0), previous: .solid(0))
        let r = scorer.score(black, dwell: 0, recentEscalated: [0])
        XCTAssertTrue(r.l.isFinite)
        XCTAssertEqual(r.quality, 0)
        XCTAssertLessThan(r.l, config.tauBase)
    }

    func testResetClearsChangeHistory() {
        var scorer = LocalScorer(config: config)
        for _ in 0..<5 { _ = scorer.score(signals(change: 40), dwell: 0, recentEscalated: []) }
        scorer.reset()
        XCTAssertEqual(scorer.score(signals(change: 40), dwell: 0, recentEscalated: []).changeSpike, 1)
    }

    func testUnusableFrameScoresZeroEvenWhenStopped() {
        // Normal view, then the lens is covered while the wearer stands still: a full change spike on a black frame.
        var scorer = LocalScorer(config: config)
        for _ in 0..<5 { _ = scorer.score(signals(change: 2, sharpness: 300), dwell: 1, recentEscalated: []) }
        let black = scorer.score(signals(change: 120, sharpness: 0, clipped: 1), dwell: 1, recentEscalated: [])
        XCTAssertEqual(black.l, 0)
    }
}
