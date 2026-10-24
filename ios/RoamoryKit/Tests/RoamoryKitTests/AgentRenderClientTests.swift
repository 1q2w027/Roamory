import AVFoundation
import XCTest
@testable import RoamoryKit

final class AgentRenderClientTests: XCTestCase {
    private let outputDir = FileManager.default.temporaryDirectory.appending(path: "AgentRenderClientTests-\(UUID().uuidString)")
    private let output = OutputFormat(width: 1080, height: 1920, fps: 30)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        HTTPStub.handler = nil
        HTTPStub.lastRequest = nil
        try? FileManager.default.removeItem(at: outputDir)
    }

    /// An agent request for `count` sample clips after the pre-pass.
    private static func request(clips count: Int) async throws -> (AgentRequest, [String: URL]) {
        let presets = try StylePresets.bundled()
        var trip = SampleTrip.trip
        trip.style = .reels
        let clips = PrePass.run(try await SampleTrip.clips(count: count, from: BundledResources.sampleClipURLs), preset: presets[.reels],
                                config: Fixtures.config)
        let request = AgentRequest(trip: trip, clips: clips, preset: presets[.reels], config: Fixtures.config)
        return (request, Dictionary(uniqueKeysWithValues: clips.map { ($0.momentId, $0.clipURL) }))
    }

    private func client(timeoutS: Double = 60) -> AgentRenderClient {
        var config = Fixtures.config
        config.agentTimeoutS = timeoutS
        config.agentPollS = 0.05
        return AgentRenderClient(
            baseURL: URL(string: "https://render.example.test")!, appToken: "secret", config: config, session: HTTPStub.session()
        )
    }

    private static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func job(_ status: String, progress: Double, error: Any = NSNull()) -> Data {
        json(["job_id": "a_1", "status": status, "progress": progress, "error": error])
    }

    func testUploadsWholeClipsThenFetchesTheResultBeforeTheVideo() async throws {
        let (request, urls) = try await Self.request(clips: 2)
        // The "server" returns a real MP4, and a result that matches its length.
        let file = try XCTUnwrap(BundledResources.sampleClipURLs.first)
        let video = try Data(contentsOf: file)
        let durationS = try await AVURLAsset(url: file).load(.duration).seconds
        let result = AgentResult(
            totalS: durationS, title: .init(text: "Kyoto", subtitle: "October 2026"),
            moments: [.init(momentId: "lab_00", startS: 0, endS: 2.5), .init(momentId: "lab_01", startS: 2.5, endS: durationS)]
        )

        let polls = Counter()
        let upload = Box<Data>()
        let paths = Box<[String]>([])
        HTTPStub.handler = { req, body in
            let auth = req.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
            paths.mutate { $0.append("\(req.httpMethod ?? "") \(req.url?.path ?? "")") }
            switch (req.httpMethod, req.url?.path) {
            case ("POST", "/v1/agent") where auth:
                upload.value = body
                return (202, Self.json(["job_id": "a_1"]))
            case ("GET", "/v1/agent/a_1") where auth:
                return polls.next() < 2 ? (200, Self.job("rendering", progress: 0.5)) : (200, Self.job("completed", progress: 1))
            case ("GET", "/v1/agent/a_1/result") where auth:
                return (200, try! JSONEncoder().encode(result))
            case ("GET", "/v1/agent/a_1/video") where auth:
                return (200, video)
            default:
                return (404, Self.json(["code": "not_found", "message": "", "retryable": false]))
            }
        }

        let progress = Box<[Double]>([])
        let out = outputDir.appending(path: "agent.mp4")
        let made = try await client().edit(request, clipURLs: urls, output: output, to: out) { p in progress.mutate { $0.append(p) } }
        XCTAssertEqual(made.result, result)
        XCTAssertEqual(made.video.output, output)
        XCTAssertEqual(made.video.url, out)
        XCTAssertEqual(made.video.durationS, result.totalS, accuracy: 0.01)
        XCTAssertEqual(try Data(contentsOf: out), video)
        XCTAssertEqual(paths.value?.suffix(2), ["GET /v1/agent/a_1/result", "GET /v1/agent/a_1/video"], "the result before the video")
        let reported = try XCTUnwrap(progress.value)
        XCTAssertEqual(reported.first, 0)
        XCTAssertEqual(reported.last, 1)
        XCTAssertTrue(reported.contains(0.2 + 0.7 * 0.5))
        XCTAssertEqual(reported, reported.sorted(), "progress only goes up")

        // The upload: the request rebased onto whole re-encoded clips, one {moment_id}.mp4 part each.
        let body = try XCTUnwrap(upload.value)
        let sent = try JSONDecoder().decode(AgentRequest.self, from: try XCTUnwrap(Self.part("request", in: body)))
        XCTAssertEqual(sent.clips.map(\.momentId), request.clips.map(\.momentId))
        XCTAssertEqual(sent.context, request.context)
        for (clip, original) in zip(sent.clips, request.clips) {
            XCTAssertEqual(clip.durationS, original.durationS, accuracy: 0.1, "\(clip.momentId) is whole, not trimmed")
            XCTAssertLessThanOrEqual(clip.proposedOutS, clip.durationS)
            XCTAssertLessThan(clip.proposedInS, clip.proposedOutS)
            let mp4 = try XCTUnwrap(Self.part("\(clip.momentId).mp4", in: body), clip.momentId)
            XCTAssertEqual(mp4[4..<8], Data("ftyp".utf8), "\(clip.momentId) is an MP4")
        }
    }

    func testFailedJobThrows() async throws {
        let (request, urls) = try await Self.request(clips: 1)
        HTTPStub.handler = { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", _): (202, Self.json(["job_id": "a_1"]))
            default: (200, Self.job("failed", progress: 0.4, error: ["code": "agent_failed", "message": "no valid submit", "retryable": false]))
            }
        }
        do {
            _ = try await client().edit(request, clipURLs: urls, output: output, to: outputDir.appending(path: "x.mp4"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RenderServiceError,
                           .jobFailed(APIError(code: "agent_failed", message: "no valid submit", retryable: false)))
        }
    }

    func testTimesOutWhileTheJobNeverFinishes() async throws {
        let (request, urls) = try await Self.request(clips: 1)
        HTTPStub.handler = { request, _ in
            request.httpMethod == "POST" ? (202, Self.json(["job_id": "a_1"])) : (200, Self.job("rendering", progress: 0.1))
        }
        let start = Date()
        do {
            _ = try await client(timeoutS: 3).edit(request, clipURLs: urls, output: output, to: outputDir.appending(path: "x.mp4"))
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? RenderServiceError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
    }

    func testRebaseKeepsTheProposedWindowInsideAShortExport() throws {
        var request = try Fixtures.decode(AgentRequest.self, "examples/agent_request_reels.json")
        request.clips = [request.clips[0]]  // 32 s, window 15–17
        let id = request.clips[0].momentId
        let same = request.rebased([ClipTrimmer.Uploaded(momentId: id, durationS: 31.98, hasAudio: true)]).clips[0]
        XCTAssertEqual([same.proposedInS, same.proposedOutS], [15, 17])
        XCTAssertEqual(same.durationS, 31.98)
        XCTAssertTrue(same.hasAudio)
        let short = request.rebased([ClipTrimmer.Uploaded(momentId: id, durationS: 16, hasAudio: false)]).clips[0]
        XCTAssertEqual([short.proposedInS, short.proposedOutS], [14, 16], "shifted earlier, same length")
    }

    /// The body of the multipart part called `name`.
    private static func part(_ name: String, in body: Data) -> Data? {
        guard let header = body.range(of: Data("name=\"\(name)\"".utf8)),
              let start = body.range(of: Data("\r\n\r\n".utf8), in: header.upperBound..<body.endIndex),
              let end = body.range(of: Data("\r\n--roamory-".utf8), in: start.upperBound..<body.endIndex)
        else { return nil }
        return body.subdata(in: start.upperBound..<end.lowerBound)
    }
}
