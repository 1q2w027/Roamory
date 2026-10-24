import Foundation

/// Answers requests from `handler` and records what was sent. A nil answer never responds (for timeouts).
final class HTTPStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest, Data) -> (Int, Data)?)?
    nonisolated(unsafe) static var lastRequest: (URLRequest, Data)?

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HTTPStub.self]
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
