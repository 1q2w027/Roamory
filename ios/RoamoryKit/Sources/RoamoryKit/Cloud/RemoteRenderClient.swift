import Foundation
import os

public enum RemoteRenderError: Error, Equatable, Sendable {
    case server(status: Int, error: APIError?)
    /// The job ended `failed` (normally `render_failed`).
    case jobFailed(APIError?)
    case timedOut
    case invalidResponse
}

/// Renders through the render service (Remotion, contracts README "Render service"): trims the clips,
/// uploads them, polls the job and downloads the MP4. The phone never retries; the coordinator falls back
/// to `Renderer` on any error.
public struct RemoteRenderClient: VideoRendering {
    public var baseURL: URL
    public var appToken: String
    /// Trip details for the graphics; one client per trip.
    public var context: RenderRequest.Context
    public var config: EditConfig
    public var session: URLSession

    private static let log = Logger(subsystem: "app.roamory", category: "render")

    public init(baseURL: URL, appToken: String, context: RenderRequest.Context, config: EditConfig, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.appToken = appToken
        self.context = context
        self.config = config
        self.session = session
    }

    /// Reads `RoamoryRenderBaseURL` and `RoamoryAppToken` from Info.plist (set from build settings, never committed).
    /// Nil when either is missing, and the phone renders locally.
    public static func fromBundle(_ bundle: Bundle = .main, config: EditConfig, trip: TripContext) -> RemoteRenderClient? {
        guard let base = bundle.object(forInfoDictionaryKey: "RoamoryRenderBaseURL") as? String, let url = URL(string: base),
              let token = bundle.object(forInfoDictionaryKey: "RoamoryAppToken") as? String, !token.isEmpty
        else { return nil }
        return RemoteRenderClient(baseURL: url, appToken: token, context: RenderRequest.Context(trip: trip), config: config)
    }

    /// Progress: trim and upload 0–0.3, render 0.3–0.9, download 0.9–1.
    /// The whole call, trimming included, is capped at `remote_render_timeout_s`.
    public func render(
        _ spec: EditSpec, clipURLs: [String: URL], to outputURL: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> RenderResult {
        let clock = ContinuousClock()
        let start = clock.now
        let duration = try await withTimeout(config.remoteRenderTimeoutS, error: RemoteRenderError.timedOut) {
            try await renderOnce(spec, clipURLs: clipURLs, to: outputURL, progress: progress)
        }
        let elapsed = (clock.now - start) / .seconds(1)
        Self.log.info("Remote-rendered \(spec.style.rawValue) \(spec.clips.count) clips, \(duration)s video in \(elapsed)s")
        return RenderResult(url: outputURL, durationS: duration, elapsedS: elapsed, spec: spec, usedHardCutRetry: false, engine: "remotion")
    }

    private func renderOnce(
        _ spec: EditSpec, clipURLs: [String: URL], to outputURL: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Double {
        let work = FileManager.default.temporaryDirectory.appending(path: "RemoteRender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }

        progress(0)
        let trimmed = try await ClipTrimmer.trim(spec, clipURLs: clipURLs, into: work, presetName: config.remoteUploadPreset)
        progress(0.1)
        let jobId = try await upload(trimmed) { progress(0.1 + 0.2 * $0) }

        var job = try await self.job(jobId)
        while job.status != .completed {
            if job.status == .failed { throw RemoteRenderError.jobFailed(job.error) }
            progress(0.3 + 0.6 * job.progress)
            try await Task.sleep(for: .seconds(config.remoteRenderPollS))
            job = try await self.job(jobId)
        }

        progress(0.9)
        try await download(jobId, to: outputURL)
        progress(1)
        return try await Renderer.verify(outputURL, expectedS: EditTimeline.totalDurationS(spec), toleranceS: config.renderDurationToleranceS)
    }

    // MARK: Requests

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var http = URLRequest(url: baseURL.appending(path: path), timeoutInterval: config.remoteRenderTimeoutS)
        http.httpMethod = method
        http.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        return http
    }

    /// `POST /v1/render`: the request JSON plus one `{moment_id}.mp4` part per clip. Returns the job id.
    private func upload(_ trimmed: ClipTrimmer.Trimmed, progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let request = RenderRequest(editSpec: trimmed.spec, context: context, clips: trimmed.clips)
        var body = MultipartBody(boundary: "roamory-\(UUID().uuidString)")
        body.part(name: "request", type: "application/json", data: try JSONEncoder().encode(request))
        for clip in trimmed.clips {
            guard let file = trimmed.files[clip.momentId] else { throw RenderError.missingClip(momentId: clip.momentId) }
            let name = "\(clip.momentId).mp4"
            body.part(name: name, filename: name, type: "video/mp4", data: try Data(contentsOf: file))
        }
        var http = self.request("v1/render", method: "POST")
        http.setValue(body.contentType, forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.upload(for: http, from: body.finished(), delegate: UploadProgress(progress))
        try Self.check(response, data, expected: 202)
        struct Accepted: Decodable { var job_id: String }
        return try JSONDecoder().decode(Accepted.self, from: data).job_id
    }

    /// `GET /v1/render/{job_id}`.
    private func job(_ jobId: String) async throws -> RenderJob {
        let (data, response) = try await session.data(for: request("v1/render/\(jobId)"))
        try Self.check(response, data, expected: 200)
        return try JSONDecoder().decode(RenderJob.self, from: data)
    }

    /// `GET /v1/render/{job_id}/video`; the server deletes the job after it.
    private func download(_ jobId: String, to outputURL: URL) async throws {
        let (file, response) = try await session.download(for: request("v1/render/\(jobId)/video"))
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
