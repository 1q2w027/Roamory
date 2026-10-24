import Foundation

/// Body of every non-2xx backend or render service response (contracts/error.schema.json).
public struct APIError: Codable, Sendable, Equatable {
    public var code: String
    public var message: String
    public var retryable: Bool
}

public enum RenderServiceError: Error, Equatable, Sendable {
    case server(status: Int, error: APIError?)
    /// The job ended `failed` (normally `agent_failed` or `agent_timeout`).
    case jobFailed(APIError?)
    case timedOut
    case invalidResponse
}

/// Codable mirror of contracts/render_job.schema.json: the body of `GET /v1/agent/{job_id}`.
public struct RenderJob: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case queued, rendering, completed, failed
    }

    public var jobId: String
    public var status: Status
    public var progress: Double
    public var error: APIError?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, progress, error
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jobId, forKey: .jobId)
        try c.encode(status, forKey: .status)
        try c.encode(progress, forKey: .progress)
        try c.encode(error, forKey: .error)
    }
}

/// The render service's job API for `AgentRenderClient` (`/v1/agent`): auth, the multipart upload, polling the job
/// and downloading the video. Errors are `RenderServiceError`.
struct RenderServiceHTTP: Sendable {
    var baseURL: URL
    var appToken: String
    /// Per-request timeout; the caller caps the whole job.
    var timeoutS: Double
    var pollS: Double
    var session: URLSession

    func request(_ path: String, method: String = "GET") -> URLRequest {
        var http = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeoutS)
        http.httpMethod = method
        http.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        return http
    }

    /// `POST {path}`: the request JSON plus one `{moment_id}.mp4` part per file. Returns the job id.
    func upload(
        _ path: String, request: Data, files: [(momentId: String, url: URL)], progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        var body = MultipartBody(boundary: "roamory-\(UUID().uuidString)")
        body.part(name: "request", type: "application/json", data: request)
        for file in files {
            let name = "\(file.momentId).mp4"
            body.part(name: name, filename: name, type: "video/mp4", data: try Data(contentsOf: file.url))
        }
        var http = self.request(path, method: "POST")
        http.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: http, from: body.finished(), delegate: UploadProgress(progress))
        try Self.check(response, data, expected: 202)
        struct Accepted: Decodable { var job_id: String }
        return try JSONDecoder().decode(Accepted.self, from: data).job_id
    }

    /// Polls `GET {jobPath}` until the job completes; throws `jobFailed` when it fails. Reports the job's progress.
    func waitForJob(_ jobPath: String, progress: @Sendable (Double) -> Void) async throws {
        var job = try await self.job(jobPath)
        while job.status != .completed {
            if job.status == .failed { throw RenderServiceError.jobFailed(job.error) }
            progress(job.progress)
            try await Task.sleep(for: .seconds(pollS))
            job = try await self.job(jobPath)
        }
    }

    private func job(_ path: String) async throws -> RenderJob {
        try JSONDecoder().decode(RenderJob.self, from: try await get(path))
    }

    /// `GET {path}`, expecting 200.
    func get(_ path: String) async throws -> Data {
        let (data, response) = try await session.data(for: request(path))
        try Self.check(response, data, expected: 200)
        return data
    }

    /// `GET {path}` into `outputURL`; the server deletes the job after it.
    func download(_ path: String, to outputURL: URL) async throws {
        let (file, response) = try await session.download(for: request(path))
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.check(response, (try? Data(contentsOf: file)) ?? Data(), expected: 200)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: file, to: outputURL)
    }

    private static func check(_ response: URLResponse, _ data: @autoclosure () -> Data, expected: Int) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw RenderServiceError.invalidResponse }
        guard status == expected else {
            throw RenderServiceError.server(status: status, error: try? JSONDecoder().decode(APIError.self, from: data()))
        }
    }
}

/// Reports upload progress, 0...1.
private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
    let onProgress: @Sendable (Double) -> Void

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }
}

/// A `multipart/form-data` body.
struct MultipartBody {
    let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func part(name: String, filename: String? = nil, type: String, data part: Data) {
        data.append(Data("--\(boundary)\r\n".utf8))
        let file = filename.map { "; filename=\"\($0)\"" } ?? ""
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\(file)\r\n".utf8))
        data.append(Data("Content-Type: \(type)\r\n\r\n".utf8))
        data.append(part)
        data.append(Data("\r\n".utf8))
    }

    func finished() -> Data {
        data + Data("--\(boundary)--\r\n".utf8)
    }
}

/// Runs `operation`, throwing `timeoutError` if it takes longer than `seconds`.
func withTimeout<T: Sendable>(
    _ seconds: Double, error timeoutError: any Error = RenderServiceError.timedOut, _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw timeoutError
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
