import XCTest
@testable import RoamoryKit

final class EscalationGateTests: XCTestCase {
    let config = try! DetectionConfig.bundled()

    /// Pushes `ls` at 2000 ms steps from `startMs` and returns the escalations.
    func push(_ g: inout EscalationGate, _ ls: [Double], dhash: UInt64 = 0, startMs: Int = 0, cloudAllowed: Bool = true) -> [Escalation] {
        ls.enumerated().compactMap { i, l in g.push(tMs: startMs + i * 2000, l: l, dhash: dhash, cloudAllowed: cloudAllowed) }
    }

    func feed(_ ls: [Double]) -> [Escalation] {
        var g = EscalationGate(config: config)
        return push(&g, ls)
    }

    func testSustainedRiseEscalatesAtPeakOneSampleLate() {
        // S = 0, 0, .72, .864, .893, .339: peak at index 4 (8000 ms), known on the next push
        XCTAssertEqual(feed([0, 0, 0.9, 0.9, 0.9, 0.2]), [Escalation(tMs: 8000, dhash: 0, l: 0.9, forced: false)])
    }

    func testSingleStrongSpikeEscalates() {
        // A scene change is one sample of high change: the next sample of the new view has change ~0.
        // S = 0, 0, .72, .144: peak at index 2 (4000 ms)
        XCTAssertEqual(feed([0, 0, 0.9, 0, 0]), [Escalation(tMs: 4000, dhash: 0, l: 0.9, forced: false)])
    }

    func testWeakBlipIsSmoothedAway() {
        // S = .24, .288, .538, .348, .31: the blip stays under tau 0.55
        XCTAssertEqual(feed([0.3, 0.3, 0.6, 0.3, 0.3]), [])
    }

    func testCooldownBlocksSecondPeak() {
        var g = EscalationGate(config: config)
        let first = push(&g, [0, 0.9, 0.9, 0.2], dhash: 0, startMs: 0)              // peak at 4000
        let tooSoon = push(&g, [0.9, 0.9, 0.2], dhash: .max, startMs: 8000)          // peak at 10_000, 6 s later
        let later = push(&g, [0, 0, 0.9, 0.9, 0.2], dhash: .max, startMs: 14_000)    // peak at 20_000
        XCTAssertEqual(first.map(\.tMs), [4000])
        XCTAssertEqual(tooSoon, [])
        XCTAssertEqual(later.map(\.tMs), [20_000])
    }

    func testSimilarFrameBlocked() {
        var g = EscalationGate(config: config)
        _ = push(&g, [0, 0.9, 0.9, 0.2], dhash: 0, startMs: 0)
        XCTAssertEqual(push(&g, [0, 0, 0, 0, 0.9, 0.9, 0.2], dhash: 0b1_1111_1111, startMs: 8000), [])          // 9 bits
        XCTAssertEqual(push(&g, [0, 0, 0, 0, 0.9, 0.9, 0.2], dhash: 0b11_1111_1111, startMs: 22_000).count, 1)  // 10 bits
    }

    func testForcedEvery30thSample() {
        XCTAssertEqual(feed(Array(repeating: 0, count: 30)), [Escalation(tMs: 58_000, dhash: 0, l: 0, forced: true)])
    }

    func testForcedRespectsCooldown() {
        var g = EscalationGate(config: config)
        let ls = Array(repeating: 0.0, count: 26) + [0.9, 0.9, 0.2, 0]  // peak at index 27 (54 s), forced at index 29 (58 s)
        let out = push(&g, ls, dhash: 0)
        XCTAssertEqual(out.map(\.tMs), [54_000])
    }

    func testCloudNotAllowedNeverEscalates() {
        var g = EscalationGate(config: config)
        XCTAssertEqual(push(&g, [0, 0.9, 0.9, 0.2] + Array(repeating: 0, count: 30), cloudAllowed: false), [])
    }

    func testThresholdTightensAsBucketDrains() {
        XCTAssertEqual(EscalationGate.threshold(tokens: 5, capacity: 5, base: 0.55, slope: 0.2), 0.55, accuracy: 1e-9)
        XCTAssertEqual(EscalationGate.threshold(tokens: 0, capacity: 5, base: 0.55, slope: 0.2), 0.75, accuracy: 1e-9)
        XCTAssertEqual(EscalationGate.threshold(tokens: 2.5, capacity: 5, base: 0.55, slope: 0.2), 0.65, accuracy: 1e-9)
    }

    func testEscalationSpendsToken() {
        var g = EscalationGate(config: config)
        _ = push(&g, [0, 0.9, 0.9, 0.2], dhash: 0, startMs: 0)
        XCTAssertEqual(g.tokens, 4, accuracy: 1e-6)  // starts full (refill capped at 5), escalation takes 1
    }

    func testEmptyBucketBlocks() {
        var g = EscalationGate(config: config)
        var count = 0
        // A peak every 12 s with a fresh hash each time: cooldown passes, but tokens refill only 0.4 per peak.
        for k in 0..<12 {
            count += push(&g, [0, 0.95, 0.95, 0.2, 0, 0], dhash: k.isMultiple(of: 2) ? 0 : .max, startMs: k * 12_000).count
        }
        XCTAssertLessThan(count, 12)
        XCTAssertGreaterThanOrEqual(count, 5)
    }

    func testDemoModeShortensCooldown() {
        var g = EscalationGate(config: config, demoMode: true)
        _ = push(&g, [0, 0.9, 0.9, 0.2], dhash: 0, startMs: 0)
        XCTAssertEqual(push(&g, [0.9, 0.9, 0.2], dhash: .max, startMs: 8000).count, 1)  // 6 s later
    }

    func testResetClearsSmoothing() {
        var g = EscalationGate(config: config)
        _ = push(&g, [0.9, 0.9], startMs: 0)
        g.reset()
        // Without the reset, the first push of the new session would confirm the old session's peak at 2000.
        XCTAssertEqual(push(&g, [0.2, 0.1], startMs: 60_000), [])
    }
}
