import Foundation
import Observation

/// One ended trip from its saved clips to a highlight video: hands the clips to `EditCoordinator`, retries a
/// failed edit and renders the same clips in another style.
@MainActor @Observable
public final class TripPipeline {
    public enum Phase: Equatable, Sendable {
        case idle
        /// `coordinator` has the planning and rendering phase.
        case editing
        /// The edit could not start; `retry()` tries again.
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var coordinator: EditCoordinator?
    public let clips: [ClipInfo]
    public private(set) var trip: TripContext
    public let tripFolder: URL

    private let planService: (any PlanService)?
    private let renderer: Renderer?
    private let remoteRenderer: @MainActor (TripContext) -> (any VideoRendering)?
    private let agent: (any AgentRendering)?

    /// - Parameters:
    ///   - folder: the trip's folder; the video goes in `{folder}/video/`.
    ///   - clips: the trip's saved clips, from `TripFolder.loadClips(in: folder)`.
    ///   - planService, remoteRenderer, agent: the cloud pieces; the defaults read Info.plist and are nil without a
    ///     configured backend, so everything then runs on the phone.
    public init(
        trip: TripContext, folder: URL, clips: [ClipInfo],
        planService: (any PlanService)? = (try? EditConfig.bundled()).flatMap { PlanClient.fromBundle(config: $0) },
        renderer: Renderer? = nil,
        remoteRenderer: @escaping @MainActor (TripContext) -> (any VideoRendering)? = { trip in
            (try? EditConfig.bundled()).flatMap { RemoteRenderClient.fromBundle(config: $0, trip: trip) }
        },
        agent: (any AgentRendering)? = (try? EditConfig.bundled()).flatMap { AgentRenderClient.fromBundle(config: $0) }
    ) {
        self.trip = trip
        self.tripFolder = folder
        self.clips = clips
        self.planService = planService
        self.renderer = renderer
        self.remoteRenderer = remoteRenderer
        self.agent = agent
    }

    public var isRunning: Bool {
        phase == .editing && (coordinator?.isRunning ?? false)
    }

    /// Plans and renders the video.
    public func start() async {
        guard !isRunning, coordinator == nil else { return }
        await edit()
    }

    /// After a failure: re-runs planning and rendering.
    public func retry() async {
        guard !isRunning else { return }
        await edit()
    }

    /// The same clips in another style.
    public func rerender(style: Style) async {
        guard !isRunning else { return }
        trip.style = style
        coordinator = nil
        await edit()
    }

    private func edit() async {
        let coordinator: EditCoordinator
        if let existing = self.coordinator {
            coordinator = existing
        } else {
            do {
                coordinator = EditCoordinator(
                    trip: trip, clips: clips, outputDirectory: tripFolder.appending(path: "video"),
                    presets: try StylePresets.bundled(), config: try EditConfig.bundled(), service: planService,
                    renderer: renderer, remoteRenderer: remoteRenderer(trip), agent: agent
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
