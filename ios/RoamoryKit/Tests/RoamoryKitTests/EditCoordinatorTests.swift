import XCTest
@testable import RoamoryKit

@MainActor
final class EditCoordinatorTests: XCTestCase {
    /// Each test renders into its own folder, removed when the test object goes away.
    private let outputDir = FileManager.default.temporaryDirectory.appending(path: "EditCoordinatorTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: outputDir)
    }

    private func coordinator(
        _ clips: [ClipInfo], style: Style = .reels, cloud: Bool = false, service: (any PlanService)? = nil,
        engine: String = "avfoundation", remote: (any VideoRendering)? = nil
    ) throws -> EditCoordinator {
        var trip = RenderLab.trip
        trip.style = style
        trip.allowCloudAnalysis = cloud
        var config = Fixtures.config
        config.renderEngine = engine
        return EditCoordinator(trip: trip, clips: clips, outputDirectory: outputDir, presets: try StylePresets.bundled(),
                               config: config, service: service, remoteRenderer: remote)
    }

    func testNoClipsIsANoMomentsError() async throws {
        let c = try coordinator([])
        await c.run()
        XCTAssertEqual(c.phase, .error(stage: .noMoments, message: "No moments were kept on this trip."))
        XCTAssertEqual(c.video?.status, .error)
    }

    func testRunsToCompletedWithButtonMomentsMarked() async throws {
        let clips = try await RenderLab.clips(count: 3, from: BundledResources.sampleClipURLs)
        let c = try coordinator(clips)
        await c.run()
        XCTAssertEqual(c.phase, .completed)
        XCTAssertEqual(c.planOutcome?.source, .fallback(reason: "cloud analysis is off"))
        let video = try XCTUnwrap(c.video)
        XCTAssertEqual(video.status, .completed)
        XCTAssertEqual(video.planSource, "fallback")
        XCTAssertEqual(video.renderEngine, "avfoundation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(video.outputPath)))
        XCTAssertEqual(c.reviewMoments.map(\.momentId), c.renderResult?.spec.clips.map(\.momentId))
        XCTAssertEqual(c.reviewMoments.filter(\.isButton).map(\.momentId), ["lab_01"])

        let saved = try Data(contentsOf: outputDir.appending(path: "generated_video.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(GeneratedVideo.self, from: saved).outputPath, video.outputPath)
    }

    func testBackendDownStillMakesAVideo() async throws {
        let clips = try await RenderLab.clips(count: 2, from: BundledResources.sampleClipURLs)
        let c = try coordinator(clips, cloud: true, service: FakePlanService { throw URLError(.cannotConnectToHost) })
        await c.run()
        XCTAssertEqual(c.phase, .completed)
        guard case .fallback = c.planOutcome?.source else { return XCTFail("expected the fallback") }
    }

    func testRetryAfterAnErrorRunsAgain() async throws {
        var clips = try await RenderLab.clips(count: 1, from: BundledResources.sampleClipURLs)
        clips[0].clipURL = URL(fileURLWithPath: "/nonexistent/clip.mp4")
        let c = try coordinator(clips)
        await c.run()
        guard case .error(.rendering, _) = c.phase else { return XCTFail("expected a render error, got \(c.phase)") }
        await c.run()
        guard case .error(.rendering, _) = c.phase else { return XCTFail("retry should run again") }
    }

    func testRemoteEngineIsUsedWhenChosenAndAllowed() async throws {
        let clips = try await RenderLab.clips(count: 2, from: BundledResources.sampleClipURLs)
        let remote = FakeRemoteRenderer()
        let c = try coordinator(clips, cloud: true, service: FakePlanService { throw URLError(.cannotConnectToHost) },
                                engine: "remotion", remote: remote)
        await c.run()
        XCTAssertEqual(c.phase, .completed)
        XCTAssertEqual(remote.calls.count, 1)
        XCTAssertEqual(c.video?.renderEngine, "remotion")
        XCTAssertEqual(c.reviewMoments.map(\.momentId), c.planOutcome?.spec.clips.map(\.momentId))
    }

    func testRemoteFailureFallsBackToAVFoundation() async throws {
        let clips = try await RenderLab.clips(count: 2, from: BundledResources.sampleClipURLs)
        for error in [RemoteRenderError.timedOut, .jobFailed(nil), .server(status: 429, error: nil)] as [any Error] + [URLError(.cannotConnectToHost)] {
            let remote = FakeRemoteRenderer(error: error)
            let c = try coordinator(clips, cloud: true, service: FakePlanService { throw URLError(.cannotConnectToHost) },
                                    engine: "remotion", remote: remote)
            await c.run()
            XCTAssertEqual(c.phase, .completed, "\(error)")
            XCTAssertEqual(remote.calls.count, 1)
            XCTAssertEqual(c.video?.renderEngine, "avfoundation", "\(error)")
            XCTAssertEqual(c.renderResult?.engine, "avfoundation")
            XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(c.video?.outputPath)))
        }
    }

    func testRemoteNeedsConsentAndTheEngineSetting() async throws {
        let clips = try await RenderLab.clips(count: 1, from: BundledResources.sampleClipURLs)
        for (cloud, engine) in [(false, "remotion"), (true, "avfoundation")] {
            let remote = FakeRemoteRenderer()
            let c = try coordinator(clips, cloud: cloud, service: FakePlanService { throw URLError(.cannotConnectToHost) },
                                    engine: engine, remote: remote)
            await c.run()
            XCTAssertEqual(c.phase, .completed)
            XCTAssertEqual(remote.calls.count, 0, "cloud \(cloud), engine \(engine)")
            XCTAssertEqual(c.video?.renderEngine, "avfoundation")
        }
    }

    func testCapKeepsButtonsThenBestScores() {
        let clips = (0..<6).map { i in
            ClipInfo(momentId: "m\(i)", source: i < 2 ? .button : .ai, score: Double(i) / 10, fromMs: i * 1000, toMs: i * 1000 + 30_000,
                     triggerS: 15, clipURL: URL(fileURLWithPath: "/c\(i).mp4"), durationS: 30)
        }
        XCTAssertEqual(EditCoordinator.capped(clips, max: 4).map(\.momentId), ["m0", "m1", "m4", "m5"])
        XCTAssertEqual(EditCoordinator.capped(clips, max: 1).map(\.momentId), ["m0", "m1"])
        XCTAssertEqual(EditCoordinator.capped(clips, max: 10).count, 6)
    }
}

/// Stands in for `RemoteRenderClient`: throws `error`, or renders locally and reports itself as Remotion.
final class FakeRemoteRenderer: VideoRendering, @unchecked Sendable {
    let error: (any Error)?
    private let lock = NSLock()
    private var recorded: [EditSpec] = []

    init(error: (any Error)? = nil) {
        self.error = error
    }

    var calls: [EditSpec] { lock.withLock { recorded } }

    func render(
        _ spec: EditSpec, clipURLs: [String: URL], to outputURL: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> RenderResult {
        lock.withLock { recorded.append(spec) }
        if let error { throw error }
        var result = try await Renderer(config: Fixtures.config).render(spec, clipURLs: clipURLs, to: outputURL, progress: progress)
        result.engine = "remotion"
        return result
    }
}
