import AVFoundation
import Foundation
import Observation
import os

/// One trip from a finished recording to a highlight video: finds the moments (TRD FINALIZING, done after
/// recording here, in place of the rolling buffer), cuts the clips, then hands them to `EditCoordinator`.
@MainActor @Observable
public final class TripPipeline {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Detection and clip cutting, 0…1.
        case finding(progress: Double)
        /// `coordinator` has the planning and rendering phase.
        case editing
        /// Finding moments failed; `retry()` starts over from the recording.
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var coordinator: EditCoordinator?
    /// Set once the clips are cut; nil until then or after a failure.
    public private(set) var clips: [ClipInfo]?
    public private(set) var trip: TripContext
    public let tripFolder: URL

    private let settings: TripSettings
    private let installId: String
    private let evaluator: (any Evaluating)?
    private let planService: (any PlanService)?
    private let renderer: Renderer?
    private let remoteRenderer: @MainActor (TripContext) -> (any VideoRendering)?
    private var recording: URL?
    private var buttonPressesMs: [Int] = []

    private static let log = Logger(subsystem: "app.roamory", category: "trip")

    /// - Parameters:
    ///   - tripsFolder: each trip gets `{tripsFolder}/{tripId}/` with `source.*`, `clips/` and `video/`.
    ///   - evaluator, planService, remoteRenderer: the cloud pieces; the defaults read Info.plist and are nil
    ///     without a configured backend, so everything then runs on the phone.
    public init(
        settings: TripSettings, tripsFolder: URL = TripPipeline.defaultTripsFolder,
        installId: String = TripSettings.installId(),
        evaluator: (any Evaluating)? = (try? DetectionConfig.bundled()).flatMap { EvaluateClient.fromBundle(config: $0) },
        planService: (any PlanService)? = (try? EditConfig.bundled()).flatMap { PlanClient.fromBundle(config: $0) },
        renderer: Renderer? = nil,
        remoteRenderer: @escaping @MainActor (TripContext) -> (any VideoRendering)? = { trip in
            (try? EditConfig.bundled()).flatMap { RemoteRenderClient.fromBundle(config: $0, trip: trip) }
        }
    ) {
        let tripId = "t_\(UUID().uuidString.prefix(8).lowercased())"
        self.settings = settings
        self.trip = settings.tripContext(tripId: tripId)
        self.tripFolder = tripsFolder.appending(path: tripId)
        self.installId = installId
        self.evaluator = evaluator
        self.planService = planService
        self.renderer = renderer
        self.remoteRenderer = remoteRenderer
    }

    public nonisolated static var defaultTripsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Trips")
    }

    public var isRunning: Bool {
        switch phase {
        case .finding: true
        case .editing: coordinator?.isRunning ?? false
        default: false
        }
    }

    /// Takes the recording into the trip folder (moved, or copied when `move` is false) and runs to a video.
    /// - Parameter buttonPressesMs: from the recording's start.
    public func start(video: URL, buttonPressesMs: [Int] = [], move: Bool = true) async {
        guard !isRunning, recording == nil else { return }
        self.buttonPressesMs = buttonPressesMs
        do {
            try FileManager.default.createDirectory(at: tripFolder, withIntermediateDirectories: true)
            let ext = video.pathExtension.isEmpty ? "mov" : video.pathExtension
            let source = tripFolder.appending(path: "source.\(ext)")
            if move {
                try FileManager.default.moveItem(at: video, to: source)
            } else {
                try FileManager.default.copyItem(at: video, to: source)
            }
            recording = source
        } catch {
            phase = .failed(message: "Could not keep the recording: \(error.localizedDescription)")
            return
        }
        await findAndEdit()
    }

    /// After a failure: finds the moments again if that failed, else re-runs planning and rendering.
    public func retry() async {
        guard !isRunning else { return }
        if clips == nil {
            await findAndEdit()
        } else {
            await edit()
        }
    }

    /// The same clips in another style.
    public func rerender(style: Style) async {
        guard !isRunning, clips != nil else { return }
        trip.style = style
        coordinator = nil
        await edit()
    }

    private func findAndEdit() async {
        guard let recording else { return }
        let started = Date()
        phase = .finding(progress: 0)
        do {
            clips = try await findClips(in: recording)
            Self.log.info("Found \(self.clips?.count ?? 0) clips in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
        } catch {
            Self.log.error("Finding moments failed: \(String(describing: error))")
            phase = .failed(message: "Could not find the moments: \(error.localizedDescription)")
            return
        }
        coordinator = nil
        await edit()
    }

    private func findClips(in recording: URL) async throws -> [ClipInfo] {
        let config = try DetectionConfig.bundled()
        let holder = CollectingHolder()
        let cloud = trip.allowCloudAnalysis && evaluator != nil
        let detector = MomentDetector(
            trip: settings.tripInfo(tripId: trip.tripId, installId: installId), config: config, holder: holder,
            evaluator: evaluator, cloudAllowed: cloud
        )
        // Detection is most of the work; cutting the clips takes the last 10 %.
        let samples = try await FileDetection.detect(
            video: recording, buttonPressesMs: buttonPressesMs, detector: detector, config: config, waitForRequests: cloud,
            progress: { p in Task { @MainActor in self.updateFinding(p * 0.9) } }
        )
        let kept = await ClipExtractor.kept(await holder.holds, detector: detector)
        let durationMs = Int(try await AVURLAsset(url: recording).load(.duration).seconds * 1000)
        let windows = ClipExtractor.windows(kept, durationMs: durationMs, config: config)
        let clipsFolder = tripFolder.appending(path: "clips")
        try? FileManager.default.removeItem(at: clipsFolder)
        let clips = try await ClipExtractor.extract(
            video: recording, windows: windows, samples: samples, tripId: trip.tripId, sessionId: "s_01", tripFolder: tripFolder
        )
        updateFinding(1)
        return clips
    }

    private func updateFinding(_ progress: Double) {
        guard case let .finding(current) = phase, progress > current else { return }
        phase = .finding(progress: progress)
    }

    private func edit() async {
        guard let clips else { return }
        let coordinator: EditCoordinator
        if let existing = self.coordinator {
            coordinator = existing
        } else {
            do {
                coordinator = EditCoordinator(
                    trip: trip, clips: clips, outputDirectory: tripFolder.appending(path: "video"),
                    presets: try StylePresets.bundled(), config: try EditConfig.bundled(), service: planService,
                    renderer: renderer, remoteRenderer: remoteRenderer(trip)
                )
            } catch {
                phase = .failed(message: "Could not load the edit settings: \(error.localizedDescription)")
                return
            }
            self.coordinator = coordinator
        }
        phase = .editing
        await coordinator.run()
    }
}
