import XCTest
@testable import RoamoryKit

actor FakeHolder: MomentHolder {
    var holds: [(triggerMs: Int, source: MomentSource)] = []
    var released: [String] = []

    func hold(triggerMs: Int, source: MomentSource) -> String {
        holds.append((triggerMs, source))
        return "m_\(holds.count)"
    }

    func release(_ momentId: String) {
        released.append(momentId)
    }
}

/// Returns queued results in call order; can hold every call until `open()`.
final class FakeEvaluator: Evaluating, @unchecked Sendable {
    private let lock = NSLock()
    private var _results: [Result<Evaluation, Error>] = []
    private var _calls: [(context: EvaluateContext, frames: [Data])] = []
    private var _blocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var results: [Result<Evaluation, Error>] {
        get { lock.withLock { _results } }
        set { lock.withLock { _results = newValue } }
    }
    var calls: [(context: EvaluateContext, frames: [Data])] { lock.withLock { _calls } }
    var blocked: Bool {
        get { lock.withLock { _blocked } }
        set { lock.withLock { _blocked = newValue } }
    }

    func open() {
        let resume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            _blocked = false
            defer { waiters.removeAll() }
            return waiters
        }
        resume.forEach { $0.resume() }
    }

    func evaluate(context: EvaluateContext, frames: [Data]) async throws -> Evaluation {
        let mustWait = lock.withLock { () -> Bool in
            _calls.append((context, frames))
            return _blocked
        }
        if mustWait {
            await withCheckedContinuation { c in
                let stillBlocked = lock.withLock { () -> Bool in
                    if _blocked { waiters.append(c) }
                    return _blocked
                }
                if !stillBlocked { c.resume() }
            }
        }
        let next = lock.withLock { () -> Result<Evaluation, Error>? in _results.isEmpty ? nil : _results.removeFirst() }
        return try (next ?? .failure(EvaluateError.network)).get()
    }
}

final class MomentDetectorTests: XCTestCase {
    let config = try! DetectionConfig.bundled()
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
    var holder: FakeHolder!
    var evaluator: FakeEvaluator!
    var detector: MomentDetector!

    let trip = TripInfo(
        tripId: "t_123", installId: "i_8f3a2c", style: .cinematic, tripType: "honeymoon",
        destination: EvaluateContext.Destination(continent: "Asia", country: "Japan", city: "Kyoto"), lengthDays: 5
    )

    override func setUp() async throws {
        holder = FakeHolder()
        evaluator = FakeEvaluator()
        detector = MomentDetector(trip: trip, config: config, holder: holder, evaluator: evaluator, cloudAllowed: true)
    }

    func decode(_ name: String) -> Evaluation {
        try! Fixtures.decode(Evaluation.self, "examples/\(name)")
    }

    func esc(_ tMs: Int, l: Double = 0.5) -> Escalation {
        Escalation(tMs: tMs, dhash: 0, l: l, forced: false)
    }

    func frame(_ tMs: Int) -> SampledFrame {
        SampledFrame(tMs: tMs, luma: .solid(128), jpeg: jpeg, dwell: 0)
    }

    func testSkipReleasesHold() async {
        evaluator.results = [.success(decode("evaluation_skip_2b.json"))]
        await detector.escalate(esc(10_000), novelty: 0.4, frames: [jpeg])
        await detector.waitForIdle()
        let released = await holder.released
        XCTAssertEqual(released, ["m_1"])
        let decision = await detector.finalDecision(for: "m_1")
        XCTAssertEqual(decision, .release)
    }

    func testSaveKeepsWithDescription() async {
        evaluator.results = [.success(decode("evaluation_save.json"))]
        await detector.escalate(esc(10_000), novelty: 0.4, frames: [jpeg])
        await detector.waitForIdle()
        let decision = await detector.finalDecision(for: "m_1")
        XCTAssertEqual(decision, .keep(source: .ai, eventType: .landmark,
                                       description: "Orange torii gates lining a stone path", score: 0.85))
        XCTAssertEqual(evaluator.calls.first?.context.purpose, .select)
        XCTAssertEqual(evaluator.calls.first?.context.local.novelty, 0.4)
    }

    func testFailureFallsBackOnLocalScore() async {
        evaluator.results = [.failure(EvaluateError.timeout), .failure(EvaluateError.timeout)]
        await detector.escalate(Escalation(tMs: 0, dhash: 0, l: 0.9, forced: false), novelty: 0.4, frames: [jpeg])
        await detector.escalate(Escalation(tMs: 20_000, dhash: .max, l: 0.6, forced: false), novelty: 0.4, frames: [jpeg])
        await detector.waitForIdle()
        let first = await detector.finalDecision(for: "m_1")
        let second = await detector.finalDecision(for: "m_2")
        XCTAssertEqual(first, .keep(source: .localFallback, eventType: nil, description: nil, score: 0.9))
        XCTAssertEqual(second, .release)
        let released = await holder.released
        XCTAssertEqual(released, [])
    }

    func testQueueOverflowDropsOldestButKeepsHold() async {
        evaluator.blocked = true
        evaluator.results = Array(repeating: .success(decode("evaluation_skip_2b.json")), count: 6)
        for i in 0..<6 { await detector.escalate(esc(i * 20_000), novelty: 0.4, frames: [jpeg]) }
        let holds = await holder.holds.count
        XCTAssertEqual(holds, 6)
        evaluator.open()
        await detector.waitForIdle()
        XCTAssertEqual(evaluator.calls.count, 5)  // 2 in flight + 3 queued
        let released = await holder.released
        XCTAssertEqual(Set(released), ["m_1", "m_2", "m_4", "m_5", "m_6"])  // m_3 was dropped from the queue
        let dropped = await detector.finalDecision(for: "m_3")
        XCTAssertEqual(dropped, .release)  // pending, l 0.5 < 0.85
    }

    func testLateAnswerAfterFinalizeIsIgnored() async {
        evaluator.blocked = true
        evaluator.results = [.success(decode("evaluation_skip_2b.json"))]
        await detector.escalate(esc(0), novelty: 0.4, frames: [jpeg])
        _ = await detector.finalDecision(for: "m_1")
        evaluator.open()
        await detector.waitForIdle()
        let released = await holder.released
        XCTAssertEqual(released, [])
    }

    func testSkipNeverReleasesButtonMoment() async {
        evaluator.results = [.success(decode("evaluation_save.json")), .success(decode("evaluation_skip_2b.json"))]
        await detector.ingest(frame(8_000))  // so the describe request has a frame
        let button = await detector.buttonPressed(atMs: 9_000)
        await detector.waitForIdle()
        await detector.escalate(esc(10_000), novelty: 0.4, frames: [jpeg])
        await detector.waitForIdle()
        let released = await holder.released
        XCTAssertEqual(released, ["m_2"])
        XCTAssertFalse(released.contains(button))
        let decision = await detector.finalDecision(for: button)
        XCTAssertEqual(decision, .keep(source: .button, eventType: .landmark,
                                       description: "Orange torii gates lining a stone path", score: 0.85))
        XCTAssertEqual(evaluator.calls.first?.context.purpose, .describe)
    }

    func testButtonKeptEvenIfDescribeFails() async {
        evaluator.results = [.failure(EvaluateError.network)]
        await detector.ingest(frame(0))
        let id = await detector.buttonPressed(atMs: 500)
        await detector.waitForIdle()
        XCTAssertEqual(evaluator.calls.count, 1)
        let decision = await detector.finalDecision(for: id)
        XCTAssertEqual(decision, .keep(source: .button, eventType: nil, description: nil, score: nil))
    }

    func testButtonWithoutFramesSendsNothing() async {
        let id = await detector.buttonPressed(atMs: 0)
        await detector.waitForIdle()
        XCTAssertEqual(evaluator.calls.count, 0)
        let decision = await detector.finalDecision(for: id)
        XCTAssertEqual(decision, .keep(source: .button, eventType: nil, description: nil, score: nil))
    }

    func testFramesNeverSpanSessions() async {
        evaluator.results = [.failure(EvaluateError.network)]
        for t in [0, 2000, 4000] { await detector.ingest(frame(t)) }
        await detector.sessionStarted()
        await detector.ingest(frame(60_000))
        _ = await detector.buttonPressed(atMs: 60_500)
        await detector.waitForIdle()
        XCTAssertEqual(evaluator.calls.last?.frames.count, 1)
        XCTAssertEqual(evaluator.calls.last?.context.local.change, 0)
        XCTAssertEqual(evaluator.calls.last?.context.sampleTMs, 60_000)
    }

    func testRecentDescriptionsNewestFirstMaxFive() async {
        for k in 1...6 {
            var e = decode("evaluation_save.json")
            e.verdict.description = "d\(k)"
            evaluator.results = [.success(e)]
            await detector.escalate(esc(k * 20_000), novelty: 0.4, frames: [jpeg])
            await detector.waitForIdle()
        }
        evaluator.results = [.success(decode("evaluation_skip_2b.json"))]
        await detector.escalate(esc(200_000), novelty: 0.4, frames: [jpeg])
        await detector.waitForIdle()
        XCTAssertEqual(evaluator.calls.last?.context.recentDescriptions, ["d6", "d5", "d4", "d3", "d2"])
    }

    func testNoConsentHoldsLocallyWithoutRequests() async {
        let local = MomentDetector(trip: trip, config: config, holder: holder, evaluator: evaluator, cloudAllowed: false)
        await local.escalate(esc(0, l: 0.9), novelty: 1, frames: [jpeg])
        await local.ingest(frame(1000))
        _ = await local.buttonPressed(atMs: 1500)
        await local.waitForIdle()
        XCTAssertEqual(evaluator.calls.count, 0)
        let decision = await local.finalDecision(for: "m_1")
        XCTAssertEqual(decision, .keep(source: .localFallback, eventType: nil, description: nil, score: 0.9))
    }

    func testIngestEscalatesOnForcedSample() async {
        evaluator.results = [.success(decode("evaluation_skip_2b.json"))]
        for i in 0..<30 { await detector.ingest(frame(i * 2000)) }  // the 30th sample is forced
        await detector.waitForIdle()
        let holds = await holder.holds
        XCTAssertEqual(holds.map(\.triggerMs), [58_000])
        XCTAssertEqual(evaluator.calls.first?.frames.count, 3)
        XCTAssertEqual(evaluator.calls.first?.context.local.forced, true)
    }

    func testNormalToBlackWhileStoppedDoesNotEscalateTheBlackFrame() async {
        for i in 0..<8 { await detector.ingest(SampledFrame(tMs: i * 2000, luma: .checkerboard, jpeg: jpeg, dwell: 1)) }
        for i in 8..<16 { await detector.ingest(SampledFrame(tMs: i * 2000, luma: .solid(0), jpeg: jpeg, dwell: 1)) }
        await detector.waitForIdle()
        let holds = await holder.holds
        XCTAssertTrue(holds.allSatisfy { $0.triggerMs < 16_000 }, "escalated a black frame: \(holds.map(\.triggerMs))")
    }
}
