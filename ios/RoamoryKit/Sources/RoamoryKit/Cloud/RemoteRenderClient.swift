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

    private var http: RenderServiceHTTP {
        RenderServiceHTTP(
            baseURL: baseURL, appToken: appToken, timeoutS: config.remoteRenderTimeoutS, pollS: config.remoteRenderPollS, session: session
        )
    }

    private func renderOnce(
        _ spec: EditSpec, clipURLs: [String: URL], to outputURL: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Double {
        let work = FileManager.default.temporaryDirectory.appending(path: "RemoteRender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }

        progress(0)
        let trimmed = try await ClipTrimmer.trim(spec, clipURLs: clipURLs, into: work, presetName: config.remoteUploadPreset)
        progress(0.1)
        // `POST /v1/render`: the rebased request plus one `{moment_id}.mp4` part per clip.
        let request = try JSONEncoder().encode(RenderRequest(editSpec: trimmed.spec, context: context, clips: trimmed.clips))
        let files = try trimmed.clips.map { clip in
            guard let file = trimmed.files[clip.momentId] else { throw RenderError.missingClip(momentId: clip.momentId) }
            return (momentId: clip.momentId, url: file)
        }
        let jobId = try await http.upload("v1/render", request: request, files: files) { progress(0.1 + 0.2 * $0) }
        try await http.waitForJob("v1/render/\(jobId)") { progress(0.3 + 0.6 * $0) }

        progress(0.9)
        try await http.download("v1/render/\(jobId)/video", to: outputURL)
        progress(1)
        return try await Renderer.verify(outputURL, expectedS: EditTimeline.totalDurationS(spec), toleranceS: config.renderDurationToleranceS)
    }
}
