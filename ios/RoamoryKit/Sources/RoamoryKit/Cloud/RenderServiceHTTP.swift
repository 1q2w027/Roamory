import Foundation

/// The render service's job API, shared by `RemoteRenderClient` (`/v1/render`) and `AgentRenderClient` (`/v1/agent`):
/// auth, the multipart upload, polling the job and downloading the video. Errors are `RemoteRenderError`.
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
            if job.status == .failed { throw RemoteRenderError.jobFailed(job.error) }
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
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw RemoteRenderError.invalidResponse }
        guard status == expected else {
            throw RemoteRenderError.server(status: status, error: try? JSONDecoder().decode(APIError.self, from: data()))
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
