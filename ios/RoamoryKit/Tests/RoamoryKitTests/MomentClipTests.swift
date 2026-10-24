import XCTest
@testable import RoamoryKit

final class MomentClipTests: XCTestCase {
    func testWindowIsPreAndPostAroundTheTrigger() {
        XCTAssertEqual(MomentWindow(triggerMs: 60_000, preS: 15, postS: 15), MomentWindow(fromMs: 45_000, toMs: 75_000))
    }

    func testWindowStopsAtSessionStart() {
        let w = MomentWindow(triggerMs: 5_000, preS: 15, postS: 15, sessionStartMs: 0)
        XCTAssertEqual(w.fromMs, 0)
        XCTAssertEqual(w.toMs, 20_000)
    }

    func testTripClockRoundTrip() {
        let clock = TripClock(originS: 1000.5)
        XCTAssertEqual(clock.bufferTime(atMs: 2_500), 1003.0, accuracy: 1e-9)
        XCTAssertEqual(clock.tripMs(atBufferTime: 1003.0), 2_500)
        XCTAssertEqual(clock.tripMs(atBufferTime: 1003.0004), 2_500)   // rounds
        XCTAssertEqual(clock.tripMs(atBufferTime: 999.0), 0)           // footage from before the trip clamps to 0
    }

    func testSidecarForMomentHasTheContractFields() throws {
        let s = ClipSidecar(momentId: "mab12cd_4", tripId: "t_1", sessionId: "s_1", source: .button,
                            triggerMs: 60_000, fromMs: 44_000, toMs: 75_500, hasAudio: true, fps: 30)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["version", "moment_id", "trip_id", "session_id", "source", "trigger_ms",
                                        "from_ms", "to_ms", "clip_path", "duration_s", "has_audio", "fps_profile", "samples"])
        XCTAssertEqual(s.version, 1)
        XCTAssertEqual(s.clipPath, "clips/mab12cd_4.mp4")
        XCTAssertEqual(s.durationS, 31.5, accuracy: 1e-9)
        XCTAssertEqual(s.fpsProfile, [.init(tS: 0, fps: 30)])
        XCTAssertEqual(s.samples, [])
        XCTAssertEqual(json["source"] as? String, "button")
    }
}
