import XCTest
@testable import RoamoryKit

final class PrePassTests: XCTestCase {
    private let config = Fixtures.config

    private func clip(_ id: String, _ hash: UInt64?, source: MomentSource = .ai, score: Double? = 0.5, at minute: Int = 0) -> ClipInfo {
        ClipInfo(momentId: id, source: source, score: score, fromMs: minute * 60_000, toMs: minute * 60_000 + 32_000,
                 triggerS: 15, bestFrameDhash: hash, clipURL: URL(fileURLWithPath: "/clips/\(id).mp4"), durationS: 32)
    }

    // MARK: Dedupe

    func testNearDuplicatesKeepTheHigherScore() {
        let base: UInt64 = 0x3c7e_1f0f_8f8c_0c00
        let clips = [
            clip("m_01", base, score: 0.78, at: 2),
            clip("m_05", base ^ 0b1011, score: 0.69, at: 50),            // 3 bits away: duplicate of m_01
            clip("m_08", base ^ 0x00ff_00ff_0000_0000, score: 0.81, at: 80),  // 16 bits away: distinct
        ]
        XCTAssertEqual(PrePass.dedupe(clips, maxHamming: 8).map(\.momentId), ["m_01", "m_08"])
        XCTAssertEqual(PrePass.dedupe(clips, maxHamming: 2).map(\.momentId), ["m_01", "m_05", "m_08"])
    }

    func testButtonClipsAreNeverDropped() {
        let hash: UInt64 = 0xffff
        let clips = [clip("ai", hash, score: 0.95), clip("b1", hash, source: .button, score: nil), clip("b2", hash, source: .button, score: nil)]
        // The buttons win over an identical AI clip, and identical buttons both stay.
        XCTAssertEqual(PrePass.dedupe(clips, maxHamming: 8).map(\.momentId), ["b1", "b2"])
    }

    func testClipsWithoutAHashAreKept() {
        let clips = [clip("a", nil), clip("b", nil), clip("c", 1), clip("d", 1, score: 0.4)]
        XCTAssertEqual(PrePass.dedupe(clips, maxHamming: 8).map(\.momentId), ["a", "b", "c"])
    }

    // MARK: Best window

    func testWindowFromTheSidecarSamples() throws {
        let sidecar = try Fixtures.decode(ClipSidecar.self, "examples/clip_sidecar_m_03.json")
        let info = ClipInfo(sidecar: sidecar, moment: MomentFields(), tripFolder: URL(fileURLWithPath: "/t"))
        // Trigger at 15 s; the sample at 17 s is sharp and steady (change 7.4), the one at 15 s shakes (18.2).
        let (inS, outS) = PrePass.bestWindow(info, lengthS: 2, config: config)
        XCTAssertEqual(outS - inS, 2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(inS, 15)
        XCTAssertGreaterThanOrEqual(outS, 15)
        XCTAssertEqual(inS, 15, accuracy: 1e-9, "the window should lean toward the steady 17 s sample")
    }

    func testWindowWithoutSamplesIsCenteredOnTheTrigger() {
        var c = clip("m", nil)
        c.triggerS = 15
        XCTAssertEqual(PrePass.bestWindow(c, lengthS: 6, config: config).0, 12, accuracy: 1e-9)
        c.triggerS = 1  // near the start: clamped inside the file
        XCTAssertEqual(PrePass.bestWindow(c, lengthS: 6, config: config).0, 0, accuracy: 1e-9)
        c.durationS = 4  // shorter than the window: the whole clip
        XCTAssertEqual(PrePass.bestWindow(c, lengthS: 6, config: config).1, 4, accuracy: 1e-9)
    }

    func testRunSetsProposedWindows() throws {
        let presets = try Fixtures.presets()
        let clips = [clip("a", 1, at: 0), clip("b", 0xffff_0000, at: 5)]
        let out = PrePass.run(clips, preset: presets[.documentary], config: config)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.allSatisfy { abs($0.proposedOutS - $0.proposedInS - 7) < 1e-9 })
    }
}
