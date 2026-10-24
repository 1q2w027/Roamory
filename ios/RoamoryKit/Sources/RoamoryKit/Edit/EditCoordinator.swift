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

/// Makes one trip's video (TRD §9): the pre-pass on the phone, then the agent in the render service picks, edits
/// and renders it. Reports progress for the Processing screen.
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
        case rendering
    }

    public private(set) var phase: Phase = .idle
    public private(set) var video: GeneratedVideo?
    /// From the agent result's moments, for Review's moment list.
    public private(set) var reviewMoments: [ReviewMoment] = []
    public private(set) var renderResult: RenderResult?
    public private(set) var agentResult: AgentResult?

    public let trip: TripContext
    public let clips: [ClipInfo]
    public let outputDirectory: URL
    private let preset: StylePreset
    private let config: EditConfig
    private let agent: (any AgentRendering)?

    private static let log = Logger(subsystem: "app.roamory", category: "edit")

    /// - Parameters:
    ///   - clips: every finalized clip of the trip.
    ///   - outputDirectory: where the MP4 and its `GeneratedVideo` JSON go.
    ///   - agent: the render service (`AgentRenderClient`); nil when it is not configured, which fails the edit.
    public init(
        trip: TripContext, clips: [ClipInfo], outputDirectory: URL, presets: StylePresets, config: EditConfig,
        agent: (any AgentRendering)?
    ) {
        self.trip = trip
        self.clips = clips
        self.outputDirectory = outputDirectory
        self.preset = presets[trip.style]
        self.config = config
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
        renderResult = nil
        agentResult = nil
        var record = GeneratedVideo(
            id: UUID(), tripId: trip.tripId, style: trip.style, status: .planning, createdAt: Date()
        )
        guard !clips.isEmpty else {
            return fail(&record, .noMoments, "No moments were kept on this trip.")
        }
        guard let agent else {
            return fail(&record, .rendering, "The render service is not configured (RoamoryRenderBaseURL).")
        }

        phase = .planning(step: "Choosing the best moments")
        let prepared = Self.capped(PrePass.run(clips, preset: preset, config: config), max: config.maxClips)

        // RENDERING: uploading needs the app in the foreground, so keep the screen awake (TRD 9.2).
        record.status = .rendering
        phase = .rendering(progress: 0)
        let idle = Self.setIdleTimerDisabled(true)
        defer { Self.setIdleTimerDisabled(idle) }
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let url = outputDirectory.appending(path: "\(trip.tripId)_\(trip.style.rawValue).mp4")
            let urls = Dictionary(prepared.map { ($0.momentId, $0.clipURL) }, uniquingKeysWith: { first, _ in first })
            let made = try await agent.edit(
                AgentRequest(trip: trip, clips: prepared, preset: preset, config: config), clipURLs: urls, output: preset.output,
                to: url, progress: progressHandler()
            )
            agentResult = made.result
            renderResult = made.video
            record.status = .completed
            record.outputPath = made.video.url.path
            record.durationS = made.video.durationS
            record.renderTimeS = made.video.elapsedS
            reviewMoments = Self.reviewMoments(made.result, clips: prepared)
            video = record
            save(record)
            phase = .completed
        } catch is CancellationError {
            fail(&record, .rendering, "Cancelled")
        } catch {
            fail(&record, .rendering, String(describing: error))
        }
    }

    /// Reports the agent's progress while the coordinator is still rendering.
    private func progressHandler() -> @Sendable (Double) -> Void {
        { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, case .rendering = self.phase else { return }
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
