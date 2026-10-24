import XCTest
@testable import RoamoryKit

/// Serves queued (status, body) responses and records what was sent.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var queue: [(Int, Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    nonisolated(unsafe) static var failWith: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(request))
        if let error = Self.failWith {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let (status, body) = Self.queue.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T, _ expected: EvaluateError,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? EvaluateError, expected, file: file, line: line)
    }
}

final class EvaluateClientTests: XCTestCase {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
    var ctx: EvaluateContext!
    var client: EvaluateClient!

    override func setUp() async throws {
        StubProtocol.queue = []
        StubProtocol.requests = []
        StubProtocol.bodies = []
        StubProtocol.failWith = nil
        ctx = try Fixtures.decode(EvaluateContext.self, "examples/evaluate_context_select.json")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = EvaluateClient(baseURL: URL(string: "http://backend.test")!, token: "test-token", timeoutS: 8,
                                session: URLSession(configuration: config))
    }

    func testSendsMultipartAndDecodes() async throws {
        StubProtocol.queue = [(200, try Fixtures.data("examples/evaluation_save.json"))]
        let r = try await client.evaluate(context: ctx, frames: [jpeg, jpeg])
        XCTAssertTrue(r.keep)
        XCTAssertEqual(r.tier, .fast)
        let req = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "http://backend.test/v1/evaluate")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(req.timeoutInterval, 8)
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: StubProtocol.bodies[0], as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="context""#))
        XCTAssertTrue(body.contains(#""trip_id":"t_123""#))
        XCTAssertTrue(body.contains(#"name="frame_0.jpg"; filename="frame_0.jpg""#))
        XCTAssertTrue(body.contains(#"name="frame_1.jpg""#))
        XCTAssertFalse(body.contains(#"name="frame_2.jpg""#))
    }

    func testServerErrorMapsToCode() async {
        StubProtocol.queue = [(429, Data(#"{"code":"rate_limited","message":"x","retryable":false}"#.utf8))]
        await XCTAssertThrowsErrorAsync(try await client.evaluate(context: ctx, frames: [jpeg]),
                                        .server(status: 429, code: "rate_limited", retryable: false))
    }

    func testServerErrorWithoutJsonBody() async {
        StubProtocol.queue = [(502, Data("<html>bad gateway</html>".utf8))]
        await XCTAssertThrowsErrorAsync(try await client.evaluate(context: ctx, frames: [jpeg]),
                                        .server(status: 502, code: "unknown", retryable: true))
    }

    func testInvalidJsonRetriedOnceThenFails() async {
        StubProtocol.queue = [(200, Data("nope".utf8)), (200, Data("nope".utf8))]
        await XCTAssertThrowsErrorAsync(try await client.evaluate(context: ctx, frames: [jpeg]), .invalidResponse)
        XCTAssertEqual(StubProtocol.requests.count, 2)
    }

    func testInvalidJsonThenValidSucceeds() async throws {
        StubProtocol.queue = [(200, Data("nope".utf8)), (200, try Fixtures.data("examples/evaluation_skip_2b.json"))]
        let r = try await client.evaluate(context: ctx, frames: [jpeg])
        XCTAssertFalse(r.keep)
    }

    func testTimeoutAndNetworkErrors() async {
        StubProtocol.failWith = URLError(.timedOut)
        await XCTAssertThrowsErrorAsync(try await client.evaluate(context: ctx, frames: [jpeg]), .timeout)
        StubProtocol.failWith = URLError(.notConnectedToInternet)
        await XCTAssertThrowsErrorAsync(try await client.evaluate(context: ctx, frames: [jpeg]), .network)
    }
}

final class EvaluateClientBundleTests: XCTestCase {
    func testFromBundleNeedsUrlAndToken() throws {
        let config = try DetectionConfig.bundled()
        XCTAssertNil(EvaluateClient.fromInfo([:], config: config))
        XCTAssertNil(EvaluateClient.fromInfo(["RoamoryAPIBaseURL": "http://mac.local:8000", "RoamoryAppToken": ""], config: config))
        XCTAssertNil(EvaluateClient.fromInfo(["RoamoryAPIBaseURL": "", "RoamoryAppToken": "t"], config: config))
        let client = try XCTUnwrap(EvaluateClient.fromInfo(["RoamoryAPIBaseURL": "http://mac.local:8000", "RoamoryAppToken": "t"],
                                                           config: config))
        XCTAssertEqual(client.baseURL.absoluteString, "http://mac.local:8000")
        XCTAssertEqual(client.timeoutS, config.evaluateTimeoutS)
    }
}
