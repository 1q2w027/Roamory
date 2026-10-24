import XCTest
@testable import RoamoryKit

final class ReplayReportTests: XCTestCase {
    func testReportCountsLabelsWithinTolerance() {
        let r = ReplayReport.compute(samples: 150, escalatedMs: [20_000, 95_000, 200_000], keptMs: [20_000, 200_000],
                                     labelsMs: [22_000, 100_000, 240_000], toleranceMs: 10_000)
        XCTAssertEqual(r.escalations, 3)
        XCTAssertEqual(r.escalationRate, 0.02, accuracy: 1e-9)
        XCTAssertEqual(r.moments.map(\.escalated), [true, true, false])
        XCTAssertEqual(r.moments.map(\.kept), [true, false, false])
    }

    func testNoSamplesHasZeroRate() {
        XCTAssertEqual(ReplayReport.compute(samples: 0, escalatedMs: [], keptMs: [], labelsMs: [], toleranceMs: 1).escalationRate, 0)
    }
}
