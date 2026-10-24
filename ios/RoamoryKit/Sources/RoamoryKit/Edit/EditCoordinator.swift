import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#endif

/// The `GeneratedVideo` record (TRD 3.3). A plain value until persistence lands; the coordinator saves it as JSON.
public struct GeneratedVideo: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case planning, rendering, completed, error
    }

    public var id: UUID
    public var tripId: String
    public var style: Style
    public var status: Status
    public var editSpec: EditSpec?
    /// "cloud", "fallback", or "agent" (agent mode, no edit spec).
    public var planSource: String?
    /// "avfoundation", "remotion" or "agent": the engine that made the file, after any fallback.
    public var renderEngine: String?
    public var outputPath: String?
    public var durationS: Double?
    public var renderTimeS: Double?
    public var createdAt: Date
    public var error: String?
}

/// A moment as Review shows it: where it plays in the video, button moments marked.
public struct ReviewMoment: Sendable, Equatable, Identifiable {
    public var momentId: String
    public var isButton: Bool
    public var description: String?
    public var startS: Double
    public var endS: Double

    public var id: String { momentId }
}

/// Runs PLANNING (pre-pass, cloud plan or fallback, validation) and RENDERING for one trip (TRD 10),
/// and reports progress for the Processing screen. In agent mode (TRD 9.3) the agent does both after the pre-pass,
/// and the normal path runs only if it fails.
@MainActor @Observable
public final class EditCoordinator {
    public enum Phase: Equatable, Sendable {
        case idle
        case planning(step: String)
        case rendering(progress: Double)
        case completed
        case error(stage: ErrorStage, message: String)
    }

    public enum ErrorStage: String, Sendable {
        case noMoments = "no_moments"
        case planning, rendering
    }

    public private(set) var phase: Phase = .idle
    public private(set) var video: GeneratedVideo?
    /// From the rendered `spec.clips`, or the agent result's moments, for Review's moment list.
    public private(set) var reviewMoments: [ReviewMoment] = []
    /// Nil when the agent made the video.
    public private(set) var planOutcome: PlanOutcome?
    public private(set) var renderResult: RenderResult?
    /// Set when the agent made the video.
    public private(set) var agentResult: AgentResult?

    public let trip: TripContext
    public let clips: [ClipInfo]
    public let outputDirectory: URL
    private let preset: StylePreset
    private let config: EditConfig
    private let service: (any PlanService)?
    private let renderer: Renderer
    private let remoteRenderer: (any VideoRendering)?
    private let agent: (any AgentRendering)?
    /// Bumped per render attempt, so a late progress update from a failed remote render is dropped.
    private var renderAttempt = 0

    private static let log = Logger(subsystem: "app.roamory", category: "edit")

    /// - Parameters:
    ///   - clips: every finalized clip of the trip.
    ///   - outputDirectory: where the MP4 and its `GeneratedVideo` JSON go.
    ///   - service: the cloud planner; nil plans on the phone.
    ///   - renderer: the on-phone engine, also the fallback for the remote one.
    ///   - remoteRenderer: the render service (`RemoteRenderClient`), used when `render_engine` is "remotion"
    ///     and cloud analysis is on; nil always renders on the phone.
    ///   - agent: agent mode (`AgentRenderClient`), used when `render_engine` is "agent" and cloud analysis is on.
    public init(
        trip: TripContext, clips: [ClipInfo], outputDirectory: URL, presets: StylePresets, config: EditConfig,
        service: (any PlanService)?, renderer: Renderer? = nil, remoteRenderer: (any VideoRendering)? = nil,
        agent: (any AgentRendering)? = nil
    ) {
        self.trip = trip
        self.clips = clips
        self.outputDirectory = outputDirectory
        self.preset = presets[trip.style]
        self.config = config
        self.service = service
        self.renderer = renderer ?? Renderer(config: config)
        self.remoteRenderer = remoteRenderer
        self.agent = agent
    }

    public var isRunning: Bool {
        switch phase {
        case .planning, .rendering: true
        default: false
        }
    }

    /// Runs from PLANNING. Also the retry action after an error.
    public func run() async {
        guard !isRunning else { return }
        reviewMoments = []
        planOutcome = nil
        renderResult = nil
        agentResult = nil
        var record = GeneratedVideo(
            id: UUID(), tripId: trip.tripId, style: trip.style, status: .planning, createdAt: Date()
        )
        guard !clips.isEmpty else {
            return fail(&record, .noMoments, "No moments were kept on this trip.")
        }

        // PLANNING
        phase = .planning(step: "Choosing the best moments")
        let prepared = Self.capped(PrePass.run(clips, preset: preset, config: config), max: config.maxPlanClips)
        if config.renderEngine == "agent", trip.allowCloudAnalysis, let agent {
            do {
                return try await runAgent(agent, clips: prepared, record: &record)
            } catch is CancellationError {
                return fail(&record, .rendering, "Cancelled")
            } catch {
                Self.log.error("Agent mode failed, planning and rendering as usual: \(String(describing: error))")
                record.status = .planning
                phase = .planning(step: "Choosing the best moments")
            }
        }
        var thumbnails: [String: [Data]] = [:]
        if trip.allowCloudAnalysis && service != nil {
            phase = .planning(step: "Preparing previews")
            for clip in prepared {
                do {
                    thumbnails[clip.momentId] = try await PrePass.thumbnails(for: clip, config: config)
                } catch {
                    Self.log.error("No thumbnails for \(clip.momentId): \(String(describing: error))")
                }
            }
        }
        let request = PlanRequest(
            trip: trip, clips: prepared, preset: preset, config: config, thumbnailCounts: thumbnails.mapValues(\.count)
        )
        phase = .planning(step: "Planning the edit")
        let outcome = await EditPlanner(preset: preset, config: config, service: service)
            .plan(request, thumbnails: thumbnails, allowCloud: trip.allowCloudAnalysis)
        planOutcome = outcome
        record.editSpec = outcome.spec
        record.planSource = outcome.source == .cloud ? "cloud" : "fallback"

        // RENDERING: needs the app in the foreground, so keep the screen awake (TRD 9.2).
        record.status = .rendering
        phase = .rendering(progress: 0)
        let idle = Self.setIdleTimerDisabled(true)
        defer { Self.setIdleTimerDisabled(idle) }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let url = outputDirectory.appending(path: "\(trip.tripId)_\(trip.style.rawValue).mp4")
            let urls = Dictionary(prepared.map { ($0.momentId, $0.clipURL) }, uniquingKeysWith: { first, _ in first })
            let result = try await render(outcome.spec, clipURLs: urls, to: url)
            record.editSpec = result.spec
            complete(&record, result, moments: Self.reviewMoments(result.spec ?? outcome.spec, clips: prepared))
        } catch {
            fail(&record, .rendering, String(describing: error))
        }
    }

    /// Agent mode: the agent picks, edits and renders in one job. Throws on any failure, so the caller falls back.
    private func runAgent(_ agent: any AgentRendering, clips prepared: [ClipInfo], record: inout GeneratedVideo) async throws {
        phase = .planning(step: "Claude is editing your video. This takes a few minutes")
        record.status = .rendering
        // Uploading needs the app in the foreground, as rendering does.
        let idle = Self.setIdleTimerDisabled(true)
        defer { Self.setIdleTimerDisabled(idle) }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appending(path: "\(trip.tripId)_\(trip.style.rawValue).mp4")
        let urls = Dictionary(prepared.map { ($0.momentId, $0.clipURL) }, uniquingKeysWith: { first, _ in first })
        let made = try await agent.edit(
            AgentRequest(trip: trip, clips: prepared, preset: preset, config: config), clipURLs: urls, output: preset.output, to: url,
            progress: { _ in }
        )
        agentResult = made.result
        record.planSource = "agent"
        record.editSpec = nil
        complete(&record, made.video, moments: Self.reviewMoments(made.result, clips: prepared))
    }

    private func complete(_ record: inout GeneratedVideo, _ result: RenderResult, moments: [ReviewMoment]) {
        renderResult = result
        record.renderEngine = result.engine
        record.status = .completed
        record.outputPath = result.url.path
        record.durationS = result.durationS
        record.renderTimeS = result.elapsedS
        reviewMoments = moments
        video = record
        save(record)
        phase = .completed
    }

    /// The remote engine when chosen and allowed; on any error or timeout from it, AVFoundation, so the video always completes.
    private func render(_ spec: EditSpec, clipURLs: [String: URL], to url: URL) async throws -> RenderResult {
        if config.renderEngine == "remotion", trip.allowCloudAnalysis, let remoteRenderer {
            do {
                return try await remoteRenderer.render(spec, clipURLs: clipURLs, to: url, progress: progressHandler())
            } catch where !(error is CancellationError) {
                Self.log.error("Remote render failed, rendering on the phone: \(String(describing: error))")
            }
        }
        return try await renderer.render(spec, clipURLs: clipURLs, to: url, progress: progressHandler())
    }

    /// Starts a render attempt (progress back to 0) and returns its progress callback.
    private func progressHandler() -> @Sendable (Double) -> Void {
        renderAttempt += 1
        let attempt = renderAttempt
        phase = .rendering(progress: 0)
        return { progress in
            Task { @MainActor [weak self] in
                guard let self, attempt == self.renderAttempt, case .rendering = self.phase else { return }
                self.phase = .rendering(progress: progress)
            }
        }
    }

    private func fail(_ record: inout GeneratedVideo, _ stage: ErrorStage, _ message: String) {
        Self.log.error("Edit failed at \(stage.rawValue): \(message)")
        record.status = .error
        record.error = "\(stage.rawValue): \(message)"
        video = record
        save(record)
        phase = .error(stage: stage, message: message)
    }

    private func save(_ record: GeneratedVideo) {
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: outputDirectory.appending(path: "generated_video.json"))
        } catch {
            Self.log.error("Could not save the GeneratedVideo record: \(String(describing: error))")
        }
    }

    /// All button clips, then the best of the rest up to `max` (the server rejects more with 413).
    static func capped(_ clips: [ClipInfo], max: Int) -> [ClipInfo] {
        guard clips.count > max else { return clips }
        let others = clips.filter { !$0.isButton }
            .sorted { ($0.score ?? -1, -$0.fromMs) > ($1.score ?? -1, -$1.fromMs) }
            .prefix(Swift.max(max - clips.count(where: \.isButton), 0))
        let keep = Set(others.map(\.momentId))
        return clips.filter { $0.isButton || keep.contains($0.momentId) }
    }

    static func reviewMoments(_ spec: EditSpec, clips: [ClipInfo]) -> [ReviewMoment] {
        let byId = Dictionary(clips.map { ($0.momentId, $0) }, uniquingKeysWith: { first, _ in first })
        return EditTimeline.slots(spec).map { slot in
            let clip = byId[slot.momentId]
            return ReviewMoment(
                momentId: slot.momentId, isButton: clip?.isButton ?? false, description: clip?.description,
                startS: slot.startS, endS: slot.endS
            )
        }
    }

    static func reviewMoments(_ result: AgentResult, clips: [ClipInfo]) -> [ReviewMoment] {
        let byId = Dictionary(clips.map { ($0.momentId, $0) }, uniquingKeysWith: { first, _ in first })
        return result.moments.map { moment in
            let clip = byId[moment.momentId]
            return ReviewMoment(
                momentId: moment.momentId, isButton: clip?.isButton ?? false, description: clip?.description,
                startS: moment.startS, endS: moment.endS
            )
        }
    }

    /// Returns the previous value.
    @discardableResult
    private static func setIdleTimerDisabled(_ disabled: Bool) -> Bool {
        #if canImport(UIKit)
        let previous = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = disabled
        return previous
        #else
        return false
        #endif
    }
}
