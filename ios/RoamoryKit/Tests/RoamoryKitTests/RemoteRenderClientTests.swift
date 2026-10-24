import AVFoundation
import XCTest
@testable import RoamoryKit

final class RemoteRenderClientTests: XCTestCase {
    private let outputDir = FileManager.default.temporaryDirectory.appending(path: "RemoteRenderClientTests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        HTTPStub.handler = nil
        HTTPStub.lastRequest = nil
        try? FileManager.default.removeItem(at: outputDir)
    }

    /// A fallback-planned reels spec over the sample clips.
    static func plan(clips count: Int) async throws -> (EditSpec, [String: URL]) {
        let clips = try await RenderLab.clips(count: count, from: BundledResources.sampleClipURLs)
        let presets = try StylePresets.bundled()
        var trip = RenderLab.trip
        trip.style = .reels
        let request = PlanRequest(trip: trip, clips: clips, preset: presets[.reels], config: Fixtures.config)
        let spec = FallbackPlanner.plan(request, preset: presets[.reels], endCardText: Fixtures.config.endCardText)
        return (spec, Dictionary(uniqueKeysWithValues: clips.map { ($0.momentId, $0.clipURL) }))
    }

    private func client(timeoutS: Double = 60) -> RemoteRenderClient {
        var config = Fixtures.config
        config.remoteRenderTimeoutS = timeoutS
        config.remoteRenderPollS = 0.05
        return RemoteRenderClient(
            baseURL: URL(string: "https://render.example.test")!, appToken: "secret",
            context: RenderRequest.Context(trip: RenderLab.trip), config: config, session: HTTPStub.session()
        )
    }

    private static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private static func job(_ status: String, progress: Double, error: Any = NSNull()) -> Data {
        json(["job_id": "r_1", "status": status, "progress": progress, "error": error])
    }

    func testUploadsPollsAndDownloads() async throws {
        let (spec, urls) = try await Self.plan(clips: 2)
        // The "server" returns a real render of the same spec.
        let local = try await Renderer(config: Fixtures.config).render(spec, clipURLs: urls, to: outputDir.appending(path: "local.mp4"))
        let video = try Data(contentsOf: local.url)

        let polls = Counter()
        let upload = Box<(URLRequest, Data)>()
        HTTPStub.handler = { request, body in
            let auth = request.value(forHTTPHeaderField: "Authorization") == "Bearer secret"
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/render") where auth:
                upload.value = (request, body)
                return (202, Self.json(["job_id": "r_1"]))
            case ("GET", "/v1/render/r_1") where auth:
                return polls.next() < 2 ? (200, Self.job("rendering", progress: 0.5)) : (200, Self.job("completed", progress: 1))
            case ("GET", "/v1/render/r_1/video") where auth:
                return (200, video)
            default:
                return (404, Self.json(["code": "not_found", "message": "", "retryable": false]))
            }
        }

        let progress = Box<[Double]>([])
        let output = outputDir.appending(path: "remote.mp4")
        let result = try await client().render(spec, clipURLs: urls, to: output) { p in progress.mutate { $0.append(p) } }
        XCTAssertEqual(result.engine, "remotion")
        XCTAssertEqual(result.url, output)
        XCTAssertEqual(result.spec, spec, "the result carries the original spec, not the rebased one")
        XCTAssertEqual(result.durationS, EditTimeline.totalDurationS(spec), accuracy: 0.5)
        XCTAssertEqual(try Data(contentsOf: output), video)
        XCTAssertEqual(polls.count, 3)
        let reported = try XCTUnwrap(progress.value)
        XCTAssertEqual(reported.first, 0)
        XCTAssertEqual(reported.last, 1)
        XCTAssertTrue(reported.contains(0.3 + 0.6 * 0.5))
        XCTAssertEqual(reported, reported.sorted(), "progress only goes up")

        // The upload: the rebased request plus one {moment_id}.mp4 part per clip.
        let (sent, body) = try XCTUnwrap(upload.value)
        XCTAssertTrue(try XCTUnwrap(sent.value(forHTTPHeaderField: "Content-Type")).hasPrefix("multipart/form-data; boundary="))
        let request = try JSONDecoder().decode(RenderRequest.self, from: try XCTUnwrap(Self.part("request", in: body)))
        XCTAssertEqual(request.context, RenderRequest.Context(trip: RenderLab.trip))
        XCTAssertEqual(request.editSpec.clips.map(\.momentId), spec.clips.map(\.momentId))
        XCTAssertTrue(request.editSpec.clips.allSatisfy { $0.inS == 0 })
        XCTAssertEqual(request.clips.map(\.momentId), spec.clips.map(\.momentId))
        for clip in request.clips {
            let mp4 = try XCTUnwrap(Self.part("\(clip.momentId).mp4", in: body), clip.momentId)
            XCTAssertEqual(mp4[4..<8], Data("ftyp".utf8), "\(clip.momentId) is an MP4")
        }
    }

    func testFailedJobThrows() async throws {
        let (spec, urls) = try await Self.plan(clips: 1)
        HTTPStub.handler = { request, _ in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", _): (202, Self.json(["job_id": "r_1"]))
            default: (200, Self.job("failed", progress: 0.4, error: ["code": "render_failed", "message": "Chrome exited", "retryable": false]))
            }
        }
        do {
            _ = try await client().render(spec, clipURLs: urls, to: outputDir.appending(path: "x.mp4"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RemoteRenderError,
                           .jobFailed(APIError(code: "render_failed", message: "Chrome exited", retryable: false)))
        }
    }

    func testBusyServerThrows() async throws {
        let (spec, urls) = try await Self.plan(clips: 1)
        HTTPStub.handler = { _, _ in (429, Self.json(["code": "busy", "message": "1 job running", "retryable": true])) }
        do {
            _ = try await client().render(spec, clipURLs: urls, to: outputDir.appending(path: "x.mp4"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RemoteRenderError,
                           .server(status: 429, error: APIError(code: "busy", message: "1 job running", retryable: true)))
        }
    }

    func testTimesOutWhileTheJobNeverFinishes() async throws {
        let (spec, urls) = try await Self.plan(clips: 1)
        HTTPStub.handler = { request, _ in
            request.httpMethod == "POST" ? (202, Self.json(["job_id": "r_1"])) : (200, Self.job("rendering", progress: 0.1))
        }
        let start = Date()
        do {
            _ = try await client(timeoutS: 3).render(spec, clipURLs: urls, to: outputDir.appending(path: "x.mp4"))
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? RemoteRenderError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 6)
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

/// A value shared with `@Sendable` stub handlers.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?

    init(_ value: T? = nil) {
        stored = value
    }

    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func mutate(_ change: (inout T) -> Void) {
        lock.withLock {
            guard var v = stored else { return }
            change(&v)
            stored = v
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    /// Returns the count before this call.
    func next() -> Int {
        lock.withLock {
            defer { count += 1 }
            return count
        }
    }
}
