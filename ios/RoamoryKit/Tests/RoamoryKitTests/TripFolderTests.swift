import AVFoundation
import XCTest
@testable import RoamoryKit

final class TripFolderTests: XCTestCase {
    /// Each test gets its own trip folder, removed when the test object goes away.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "TripFolderTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes `clips/{id}.json` and, unless `mp4` is false, an empty `clips/{id}.mp4`.
    private func addClip(_ id: String, source: MomentSource = .ai, fromMs: Int, triggerMs: Int, toMs: Int,
                         mp4: Bool = true) throws {
        let clips = folder.appending(path: "clips")
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        let sidecar = ClipSidecar(momentId: id, tripId: "t_1", sessionId: "s_1", source: source, triggerMs: triggerMs,
                                  fromMs: fromMs, toMs: toMs, hasAudio: false, fps: 30)
        try JSONEncoder().encode(sidecar).write(to: clips.appending(path: "\(id).json"))
        if mp4 { try Data().write(to: clips.appending(path: "\(id).mp4")) }
    }

    func testMomentFieldsRoundTripWithSnakeCaseKeys() throws {
        let f = MomentFields(eventType: .landmark, description: "Torii gate at dusk", score: 0.82)
        let data = try JSONEncoder().encode(f)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["event_type", "description", "score"])
        XCTAssertEqual(try JSONDecoder().decode(MomentFields.self, from: data), f)
    }

    func testLoadsClipsWithTheirMomentFieldsInTimeOrder() throws {
        try addClip("m_a", fromMs: 40_000, triggerMs: 55_000, toMs: 70_000)
        try addClip("m_b", source: .button, fromMs: 10_000, triggerMs: 25_000, toMs: 40_000)
        try TripFolder.saveMoment(MomentFields(eventType: .landmark, description: "Torii gate at dusk", score: 0.82),
                                  momentId: "m_a", in: folder)

        let clips = TripFolder.loadClips(in: folder)
        XCTAssertEqual(clips.map(\.momentId), ["m_b", "m_a"])
        XCTAssertEqual(clips[1].description, "Torii gate at dusk")
        XCTAssertEqual(clips[1].eventType, .landmark)
        XCTAssertEqual(clips[1].score, 0.82)
        XCTAssertEqual(clips[1].triggerS, 15, accuracy: 1e-9)
        XCTAssertEqual(clips[1].clipURL.standardizedFileURL, folder.appending(path: "clips/m_a.mp4").standardizedFileURL)
        XCTAssertNil(clips[0].description)
        XCTAssertTrue(clips[0].isButton)
    }

    func testSkipsPartialAndUnreadableClips() throws {
        try addClip("m_ok", fromMs: 0, triggerMs: 15_000, toMs: 30_000)
        try addClip("m_partial", fromMs: 30_000, triggerMs: 45_000, toMs: 60_000, mp4: false)
        try Data().write(to: folder.appending(path: "clips/m_orphan.mp4"))
        try Data("not json".utf8).write(to: folder.appending(path: "clips/junk.json"))
        XCTAssertEqual(TripFolder.loadClips(in: folder).map(\.momentId), ["m_ok"])
    }

    func testNoClipsFolderIsEmpty() {
        XCTAssertEqual(TripFolder.loadClips(in: folder).count, 0)
    }

    /// The handoff to the editor: clips read back from a trip folder are valid `EditCoordinator` input.
    @MainActor
    func testLoadedTripMakesAVideo() async throws {
        let clips = folder.appending(path: "clips")
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        for (k, source) in BundledResources.sampleClipURLs.prefix(2).enumerated() {
            let id = "m_\(k + 1)"
            try FileManager.default.copyItem(at: source, to: clips.appending(path: "\(id).mp4"))
            let durationMs = Int(try await AVURLAsset(url: source).load(.duration).seconds * 1000)
            let fromMs = 10_000 * (k + 1)
            try addClip(id, source: k == 0 ? .button : .ai, fromMs: fromMs, triggerMs: fromMs + durationMs / 2,
                        toMs: fromMs + durationMs, mp4: false)
        }

        var trip = SampleTrip.trip
        trip.style = .reels
        let agent = FakeAgent()
        let c = EditCoordinator(trip: trip, clips: TripFolder.loadClips(in: folder),
                                outputDirectory: folder.appending(path: "video"),
                                presets: try StylePresets.bundled(), config: Fixtures.config, agent: agent)
        await c.run()
        XCTAssertEqual(c.phase, .completed)
        let sent = try XCTUnwrap(agent.requests.first)
        XCTAssertEqual(sent.clips.map(\.momentId), ["m_1", "m_2"])
        XCTAssertEqual(sent.clips.first?.source, .button)
    }
}
