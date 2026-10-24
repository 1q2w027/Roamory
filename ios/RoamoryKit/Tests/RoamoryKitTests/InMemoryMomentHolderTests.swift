import XCTest
@testable import RoamoryKit

final class InMemoryMomentHolderTests: XCTestCase {
    func testDueOnlyAfterTheWindowCloses() async {
        let holder = InMemoryMomentHolder(postS: 15)
        await holder.hold(momentId: "m_1", triggerMs: 10_000, source: .ai)
        let early = await holder.due(atMs: 26_999)   // window closes at 10 s + 15 s + 2 s
        let late = await holder.due(atMs: 27_000)
        XCTAssertEqual(early, [])
        XCTAssertEqual(late, ["m_1"])
    }

    func testFinalizedMomentsAreNotDueAgain() async {
        let holder = InMemoryMomentHolder()
        await holder.hold(momentId: "m_1", triggerMs: 0, source: .button)
        await holder.hold(momentId: "m_2", triggerMs: 1_000, source: .ai)
        await holder.markFinalized("m_1")
        let due = await holder.due(atMs: 60_000)
        XCTAssertEqual(due, ["m_2"])
        let pending = await holder.pending()
        XCTAssertEqual(pending, ["m_2"])
    }

    func testReleaseIsIdempotentAndRecorded() async {
        let holder = InMemoryMomentHolder()
        await holder.hold(momentId: "m_1", triggerMs: 0, source: .ai)
        await holder.release("m_1")
        await holder.release("m_1")
        let released = await holder.released
        XCTAssertEqual(released, ["m_1"])
        let holds = await holder.holds
        XCTAssertEqual(holds.map(\.id), ["m_1"])
    }
}
