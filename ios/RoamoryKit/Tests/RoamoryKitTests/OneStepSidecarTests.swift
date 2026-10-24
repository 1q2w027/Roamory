import XCTest
@testable import RoamoryKit

final class OneStepSidecarTests: XCTestCase {
    private func make(
        source: MomentSource = .ai, triggerMs: Int = 25_000, savedAtMs: Int, prerollS: Double, durationS: Double = 45
    ) -> ClipSidecar {
        OneStepSidecar.make(
            momentId: "m_1", tripId: "t_1", sessionId: "s_1", source: source, triggerMs: triggerMs,
            savedAtMs: savedAtMs, prerollS: prerollS, durationS: durationS, hasAudio: false
        )
    }

    func testFromMsIsSaveTimeMinusPreroll() {
        let sidecar = make(savedAtMs: 40_000, prerollS: 30, durationS: 45)
        XCTAssertEqual(sidecar.fromMs, 10_000)
        XCTAssertEqual(sidecar.toMs, 10_000 + 45_000)
    }

    func testFromMsClampedToZeroEarlyInSession() {
        let sidecar = make(savedAtMs: 5_000, prerollS: 12)
        XCTAssertEqual(sidecar.fromMs, 0)
    }

    func testTriggerAndPathAreCarriedThrough() {
        let sidecar = make(source: .button, triggerMs: 25_000, savedAtMs: 40_000, prerollS: 30)
        XCTAssertEqual(sidecar.triggerMs, 25_000)
        XCTAssertEqual(sidecar.clipPath, "clips/m_1.mp4")
        XCTAssertEqual(sidecar.source, .button)
    }
}
