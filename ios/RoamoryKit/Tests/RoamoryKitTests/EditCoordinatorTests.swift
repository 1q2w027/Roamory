import XCTest
@testable import RoamoryKit

@MainActor
final class EditCoordinatorTests: XCTestCase {
    /// Each test renders into its own folder, removed when the test object goes away.
    private let outputDir = FileManager.default.temporaryDirectory.appending(path: "EditCoordinatorTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: outputDir)
    }

    private func coordinator(_ clips: [ClipInfo], style: Style = .reels, agent: (any AgentRendering)? = FakeAgent()) throws -> EditCoordinator {
        var trip = SampleTrip.trip
        trip.style = style
        return EditCoordinator(trip: trip, clips: clips, outputDirectory: outputDir, presets: try StylePresets.bundled(),
                               config: Fixtures.config, agent: agent)
    }

    func testNoClipsIsANoMomentsError() async throws {
        let c = try coordinator([])
        await c.run()
        XCTAssertEqual(c.phase, .error(stage: .noMoments, message: "No moments were kept on this trip."))
        XCTAssertEqual(c.video?.status, .error)
    }

    func testAgentMakesTheVideoAndReviewMomentsComeFromItsResult() async throws {
        let clips = try await SampleTrip.clips(count: 3, from: BundledResources.sampleClipURLs)
        let agent = FakeAgent()
        let c = try coordinator(clips, agent: agent)
        await c.run()
        XCTAssertEqual(c.phase, .completed)
        XCTAssertEqual(agent.requests.map { $0.clips.map(\.momentId) }, [["lab_00", "lab_01", "lab_02"]], "every candidate clip")
        let video = try XCTUnwrap(c.video)
        XCTAssertEqual(video.status, .completed)
        XCTAssertEqual(video.durationS, 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(video.outputPath)))
        XCTAssertEqual(c.agentResult, FakeAgent.result)
        XCTAssertEqual(c.reviewMoments, [
            ReviewMoment(momentId: "lab_01", isButton: true, description: nil, startS: 0, endS: 12),
            ReviewMoment(momentId: "lab_02", isButton: false, description: nil, startS: 12, endS: 30),
        ])

        let saved = try Data(contentsOf: outputDir.appending(path: "generated_video.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(GeneratedVideo.self, from: saved).outputPath, video.outputPath)
    }

    func testAgentFailureIsARenderingErrorAndRetryRunsAgain() async throws {
        let clips = try await SampleTrip.clips(count: 2, from: BundledResources.sampleClipURLs)
        for error in [RenderServiceError.timedOut, .jobFailed(APIError(code: "agent_failed", message: "", retryable: false)),
                      .server(status: 429, error: nil)] as [any Error] + [URLError(.cannotConnectToHost)] {
            let agent = FakeAgent(error: error)
            let c = try coordinator(clips, agent: agent)
            await c.run()
            guard case .error(.rendering, _) = c.phase else { return XCTFail("expected a rendering error for \(error), got \(c.phase)") }
            XCTAssertEqual(c.video?.status, .error)
            XCTAssertNil(c.agentResult)
            await c.run()
            XCTAssertEqual(agent.requests.count, 2, "retry calls the agent again")
        }
    }

    func testNoRenderServiceIsAnError() async throws {
        let clips = try await SampleTrip.clips(count: 1, from: BundledResources.sampleClipURLs)
        let c = try coordinator(clips, agent: nil)
        await c.run()
        guard case .error(.rendering, _) = c.phase else { return XCTFail("expected a rendering error, got \(c.phase)") }
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

/// Stands in for `AgentRenderClient`: throws `error`, or writes a placeholder file and returns `result`.
final class FakeAgent: AgentRendering, @unchecked Sendable {
    static let result = AgentResult(
        totalS: 30, title: .init(text: "Kyoto", subtitle: nil),
        moments: [.init(momentId: "lab_01", startS: 0, endS: 12), .init(momentId: "lab_02", startS: 12, endS: 30)]
    )

    let error: (any Error)?
    private let lock = NSLock()
    private var recorded: [AgentRequest] = []

    init(error: (any Error)? = nil) {
        self.error = error
    }

    var requests: [AgentRequest] { lock.withLock { recorded } }

    func edit(
        _ request: AgentRequest, clipURLs: [String: URL], output: OutputFormat, to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AgentRender {
        lock.withLock { recorded.append(request) }
        if let error { throw error }
        try Data("mp4".utf8).write(to: outputURL)
        let video = RenderResult(url: outputURL, durationS: Self.result.totalS, elapsedS: 1, output: output)
        return AgentRender(video: video, result: Self.result)
    }
}
