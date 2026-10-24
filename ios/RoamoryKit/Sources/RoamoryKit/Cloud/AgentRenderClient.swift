import Foundation
import os

/// A finished agent-mode video.
public struct AgentRender: Sendable {
    /// Engine "agent", no edit spec.
    public var video: RenderResult
    /// What the agent put in the video; Review's moments are `result.moments`.
    public var result: AgentResult
}

/// Agent mode (TRD 9.3): a Claude agent in the render service selects, edits and renders the whole video.
public protocol AgentRendering: Sendable {
    /// - Parameters:
    ///   - request: every candidate clip, with the phone's file durations (`AgentRequest(trip:clips:preset:config:)`).
    ///   - clipURLs: the clip file for each `moment_id` in the request.
    ///   - output: the style preset's size and fps, which the server also uses.
    ///   - progress: 0...1.
    func edit(
        _ request: AgentRequest, clipURLs: [String: URL], output: OutputFormat, to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AgentRender
}

/// Talks to `/v1/agent` (contracts README, "Agent mode"): re-encodes each clip whole, uploads them, polls the job,
/// fetches the result and then the MP4, and checks the file against the result. The phone never retries; the
/// coordinator plans and renders as usual on any error.
public struct AgentRenderClient: AgentRendering {
    public var baseURL: URL
    public var appToken: String
    public var config: EditConfig
    public var session: URLSession

    private static let log = Logger(subsystem: "app.roamory", category: "agent")

    public init(baseURL: URL, appToken: String, config: EditConfig, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.appToken = appToken
        self.config = config
        self.session = session
    }

    /// The render service from Info.plist, as `RemoteRenderClient.fromBundle`; nil when it is not configured.
    public static func fromBundle(_ bundle: Bundle = .main, config: EditConfig) -> AgentRenderClient? {
        guard let base = bundle.object(forInfoDictionaryKey: "RoamoryRenderBaseURL") as? String, let url = URL(string: base),
              let token = bundle.object(forInfoDictionaryKey: "RoamoryAppToken") as? String, !token.isEmpty
        else { return nil }
        return AgentRenderClient(baseURL: url, appToken: token, config: config)
    }

    /// Progress: re-encode 0–0.1, upload 0.1–0.2, agent job 0.2–0.9, download 0.9–1.
    /// The whole call, re-encoding included, is capped at `agent_timeout_s`.
    public func edit(
        _ request: AgentRequest, clipURLs: [String: URL], output: OutputFormat, to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> AgentRender {
        let clock = ContinuousClock()
        let start = clock.now
        let (duration, result) = try await withTimeout(config.agentTimeoutS, error: RemoteRenderError.timedOut) {
            try await editOnce(request, clipURLs: clipURLs, to: outputURL, progress: progress)
        }
        let elapsed = (clock.now - start) / .seconds(1)
        Self.log.info("Agent made \(request.style.rawValue) from \(request.clips.count) clips, \(result.moments.count) used, \(duration)s video in \(elapsed)s")
        let video = RenderResult(url: outputURL, durationS: duration, elapsedS: elapsed, output: output, engine: "agent")
        return AgentRender(video: video, result: result)
    }

    private var http: RenderServiceHTTP {
        RenderServiceHTTP(baseURL: baseURL, appToken: appToken, timeoutS: config.agentTimeoutS, pollS: config.remoteRenderPollS, session: session)
    }

    private func editOnce(
        _ request: AgentRequest, clipURLs: [String: URL], to outputURL: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Double, AgentResult) {
        let work = FileManager.default.temporaryDirectory.appending(path: "AgentRender-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }

        progress(0)
        let ids = request.clips.map(\.momentId)
        let whole = try await ClipTrimmer.whole(ids, clipURLs: clipURLs, into: work, presetName: config.agentUploadPreset)
        progress(0.1)
        let body = try JSONEncoder().encode(request.rebased(whole.clips))
        let files = try ids.map { id in
            guard let file = whole.files[id] else { throw RenderError.missingClip(momentId: id) }
            return (momentId: id, url: file)
        }
        let jobId = try await http.upload("v1/agent", request: body, files: files) { progress(0.1 + 0.1 * $0) }
        try await http.waitForJob("v1/agent/\(jobId)") { progress(0.2 + 0.7 * $0) }

        // The result first: downloading the video deletes the job.
        let result = try JSONDecoder().decode(AgentResult.self, from: try await http.get("v1/agent/\(jobId)/result"))
        progress(0.9)
        try await http.download("v1/agent/\(jobId)/video", to: outputURL)
        progress(1)
        let duration = try await Renderer.verify(outputURL, expectedS: result.totalS, toleranceS: config.renderDurationToleranceS)
        return (duration, result)
    }
}
