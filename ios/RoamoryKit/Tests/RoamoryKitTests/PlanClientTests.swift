import XCTest
@testable import RoamoryKit

/// Answers requests from `handler` and records what was sent. A nil answer never responds (for timeouts).
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest, Data) -> (Int, Data)?)?
    nonisolated(unsafe) static var lastRequest: (URLRequest, Data)?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        Self.lastRequest = (request, body)
        guard let (status, data) = Self.handler?(request, body) else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

final class PlanClientTests: XCTestCase {
    private func client(timeoutS: Double = 5) -> PlanClient {
        PlanClient(baseURL: URL(string: "https://api.example.test")!, appToken: "secret", timeoutS: timeoutS, session: StubProtocol.session())
    }

    private func request() throws -> PlanRequest {
        var request = try Fixtures.planRequest(.reels)
        request.clips = Array(request.clips.prefix(2))
        request.clips[0].thumbnailCount = 2
        request.clips[1].thumbnailCount = 1
        return request
    }

    override func tearDown() {
        StubProtocol.handler = nil
        StubProtocol.lastRequest = nil
    }

    func testSendsMultipartWithTokenAndDecodesTheSpec() async throws {
        let spec = try Fixtures.data("examples/edit_spec_reels.json")
        StubProtocol.handler = { _, _ in (200, spec) }
        let thumbs = ["m_01": [Data([0xFF, 0xD8, 1]), Data([0xFF, 0xD8, 2]), Data([0xFF, 0xD8, 3])], "m_02": [Data([0xFF, 0xD8, 4])]]
        let result = try await client().plan(try request(), thumbnails: thumbs)
        XCTAssertEqual(result, try Fixtures.editSpec(.reels))

        let (sent, body) = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.example.test/v1/plan")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let contentType = try XCTUnwrap(sent.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"request\""))
        // Only thumbnail_count parts per clip, named {moment_id}_{k}.jpg.
        XCTAssertTrue(text.contains("name=\"m_01_0.jpg\""))
        XCTAssertTrue(text.contains("name=\"m_01_1.jpg\""))
        XCTAssertFalse(text.contains("m_01_2.jpg"))
        XCTAssertTrue(text.contains("name=\"m_02_0.jpg\""))
    }

    func testRequestPartIsTheContractJSON() throws {
        let request = try request()
        let body = try PlanClient.multipartBody(request, thumbnails: [:], boundary: "B")
        let text = String(decoding: body, as: UTF8.self)
        let json = try XCTUnwrap(text.components(separatedBy: "\r\n\r\n").dropFirst().first?.components(separatedBy: "\r\n--B").first)
        XCTAssertEqual(try JSONDecoder().decode(PlanRequest.self, from: Data(json.utf8)), request)
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
    }

    func testErrorResponsesCarryTheErrorBody() async throws {
        StubProtocol.handler = { _, _ in (422, Data(#"{"code":"invalid_plan","message":"failed twice","retryable":false}"#.utf8)) }
        do {
            _ = try await client().plan(try request(), thumbnails: [:])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PlanClientError,
                           .server(status: 422, error: APIError(code: "invalid_plan", message: "failed twice", retryable: false)))
        }
    }

    func testTimesOut() async throws {
        StubProtocol.handler = { _, _ in nil }
        let start = Date()
        do {
            _ = try await client(timeoutS: 0.3).plan(try request(), thumbnails: [:])
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? PlanClientError, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}

/// Returns a canned spec or throws.
struct FakePlanService: PlanService {
    var result: @Sendable () throws -> EditSpec
    func plan(_ request: PlanRequest, thumbnails: [String: [Data]]) async throws -> EditSpec { try result() }
}

final class EditPlannerTests: XCTestCase {
    private func planner(_ service: (any PlanService)?) throws -> EditPlanner {
        EditPlanner(preset: try Fixtures.presets()[.reels], config: Fixtures.config, service: service)
    }

    func testValidCloudSpecIsUsed() async throws {
        let spec = try Fixtures.editSpec(.reels)
        let outcome = try await planner(FakePlanService { spec }).plan(try Fixtures.planRequest(.reels), thumbnails: [:], allowCloud: true)
        XCTAssertEqual(outcome.source, .cloud)
        XCTAssertEqual(outcome.spec, spec)
    }

    func testFallbackWhenCloudFailsIsInvalidOrOff() async throws {
        let request = try Fixtures.planRequest(.reels)
        var spec = try Fixtures.editSpec(.reels)
        spec.clips.removeAll { $0.momentId == "m_06" }  // drops a button moment
        let broken = spec

        let cases: [(String, (any PlanService)?, Bool)] = [
            ("422", FakePlanService { throw PlanClientError.server(status: 422, error: nil) }, true),
            ("timeout", FakePlanService { throw PlanClientError.timedOut }, true),
            ("network", FakePlanService { throw URLError(.notConnectedToInternet) }, true),
            ("invalid spec", FakePlanService { broken }, true),
            ("consent off", FakePlanService { XCTFail("must not call the cloud"); return broken }, false),
            ("no backend", nil, true),
        ]
        for (name, service, allowCloud) in cases {
            let outcome = try await planner(service).plan(request, thumbnails: [:], allowCloud: allowCloud)
            guard case .fallback = outcome.source else { return XCTFail("\(name): expected the fallback") }
            XCTAssertEqual(outcome.violations, [], name)
            XCTAssertTrue(outcome.spec.clips.contains { $0.momentId == "m_06" }, name)
        }
    }
}
