import Combine
import CoreMedia
import CoreVideo
import Foundation
import RoamoryKit
import UIKit
import os

/// What the recording screen shows about detection.
struct DetectionSummary: Equatable {
    var holds = 0
    var keptAI = 0
    var keptButton = 0
    var keptFallback = 0
    var released = 0
    /// Kept moments written to the trip folder, and those that could not be.
    var saved = 0
    var saveFailed = 0
    var lastDescription: String?
    var cloud = false
}

/// Connects the camera to Stage 1 detection (TRD §6): frames → `MomentDetector` → holds → keep or release.
/// A kept moment is cut out of the ring buffer (TRD §5) by `MomentClipStore`. `InMemoryMomentHolder` only keeps the
/// books: the footage is protected by the buffer's 45 s retention, which outlasts the time from a window's start to
/// its decision (pre + post + 5 s).
@MainActor
final class DetectionController: ObservableObject {
    @Published private(set) var summary = DetectionSummary()
    @Published private(set) var isRunning = false
    /// Give `sink.handle` to `CameraService.onFrame`.
    let sink = FrameSink()
    let config = try? DetectionConfig.bundled()
    /// Seconds between frames for `CameraService.frameInterval`.
    var frameInterval: TimeInterval { config?.sampleIntervalS ?? 2 }
    /// The backend URL from Info.plist (Local.xcconfig), for the settings screen; nil when unset.
    var backend: String? {
        guard let config, EvaluateClient.fromBundle(config: config) != nil else { return nil }
        return Bundle.main.object(forInfoDictionaryKey: "RoamoryAPIBaseURL") as? String
    }

    private let motion = MotionDwell()
    private var detector: MomentDetector?
    private var holder: InMemoryMomentHolder?
    private var store: MomentClipStore?
    private var consumer: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var clock = TripClock(originS: 0)
    private let log = Logger(subsystem: "com.roamory.Roamory", category: "detection")

    /// Trip clock: milliseconds since recording started.
    private var nowMs: Int { clock.tripMs(atBufferTime: Self.clockNow()) }

    /// Now on the capture session's clock (host time), which stamps the buffered samples.
    nonisolated static func clockNow() -> Double {
        CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    /// Each recording is one trip for now (no trip setup yet); its first session starts here.
    func start(_ settings: DetectionSettings, recorder: RollingRecorder) {
        guard let config, detector == nil else { return }
        let evaluator = settings.cloudAllowed ? EvaluateClient.fromBundle(config: config) : nil
        let trip = TripInfo(
            tripId: "t_\(UUID().uuidString.prefix(8).lowercased())", installId: DetectionSettings.installId(),
            style: settings.style, tripType: settings.tripType,
            destination: .init(continent: nil, country: settings.country, city: settings.city.isEmpty ? nil : settings.city),
            lengthDays: 1
        )
        let holder = InMemoryMomentHolder(postS: config.postS)
        let detector = MomentDetector(trip: trip, config: config, holder: holder, evaluator: evaluator,
                                      cloudAllowed: evaluator != nil, demoMode: settings.demoMode)
        self.holder = holder
        self.detector = detector
        clock = TripClock(originS: Self.clockNow())
        store = MomentClipStore(recorder: recorder, tripId: trip.tripId, clock: clock)
        summary = DetectionSummary(cloud: evaluator != nil)
        isRunning = true
        log.info("start trip=\(trip.tripId, privacy: .public) cloud=\(evaluator != nil) demo=\(settings.demoMode)")

        motion.start()
        let (frames, continuation) = AsyncStream.makeStream(of: SampledFrame.self, bufferingPolicy: .bufferingNewest(2))
        sink.begin(config: config, clock: clock, dwell: { [motion] in motion.current }, continuation: continuation)
        // One task ingests in order; MomentDetector's peak and change logic depend on it.
        consumer = Task {
            for await frame in frames { await detector.ingest(frame) }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.finalizeDue()
            }
        }
    }

    /// Recording stopped: every pending moment is decided now with what is known (TRD §4.4).
    func stop() async {
        guard let detector, let holder else { return }
        sink.end()
        ticker?.cancel()
        await consumer?.value
        for id in await holder.pending() {
            await finalize(id, detector: detector, holder: holder)
        }
        motion.stop()
        log.info("stop holds=\(self.summary.holds) kept=\(self.summary.keptAI + self.summary.keptButton + self.summary.keptFallback) released=\(self.summary.released)")
        self.detector = nil
        self.holder = nil
        store = nil
        consumer = nil
        ticker = nil
        isRunning = false
    }

    /// A Bluetooth remote, a volume key or the on-screen button (TRD §7): always kept.
    func buttonPressed() {
        guard let detector else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let at = nowMs
        Task {
            _ = await detector.buttonPressed(atMs: at)
            await refreshHolds()
        }
    }

    private func finalizeDue() async {
        guard let detector, let holder else { return }
        await refreshHolds()
        for id in await holder.due(atMs: nowMs) {
            await finalize(id, detector: detector, holder: holder)
        }
    }

    /// Decides a moment and, when it is kept, saves its clip in the background, so stopping never waits on a write.
    private func finalize(_ id: String, detector: MomentDetector, holder: InMemoryMomentHolder) async {
        let decision = await detector.finalDecision(for: id)
        record(decision, id: id)
        if case .keep(let source, _, _, _) = decision, let config, let store,
           let hold = await holder.holds.first(where: { $0.id == id }) {
            let window = MomentWindow(triggerMs: hold.triggerMs, preS: config.preS, postS: config.postS)
            Task {
                do {
                    let url = try await store.save(momentId: id, source: source, triggerMs: hold.triggerMs, window: window)
                    summary.saved += 1
                    log.info("saved \(id, privacy: .public) \(url.lastPathComponent, privacy: .public)")
                } catch {
                    summary.saveFailed += 1
                    log.error("save failed \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        await holder.markFinalized(id)
    }

    private func refreshHolds() async {
        guard let holder else { return }
        summary.holds = await holder.holds.count
    }

    private func record(_ decision: MomentDecision, id: String) {
        switch decision {
        case .keep(let source, _, let description, let score):
            switch source {
            case .ai: summary.keptAI += 1
            case .button: summary.keptButton += 1
            case .localFallback: summary.keptFallback += 1
            }
            if let description { summary.lastDescription = description }
            log.info("keep \(id, privacy: .public) source=\(source.rawValue, privacy: .public) score=\(score ?? -1)")
        case .release:
            summary.released += 1
            log.info("release \(id, privacy: .public)")
        }
    }
}

/// Runs on the camera's frame queue: turns a frame into a `SampledFrame` and hands it to the detector.
/// The pixel buffer is only valid during `handle`, so the conversion happens there.
nonisolated final class FrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var config: DetectionConfig?
    private var clock = TripClock(originS: 0)
    private var dwell: (@Sendable () -> Double)?
    private var continuation: AsyncStream<SampledFrame>.Continuation?

    func begin(config: DetectionConfig, clock: TripClock, dwell: @escaping @Sendable () -> Double,
               continuation: AsyncStream<SampledFrame>.Continuation) {
        lock.withLock {
            self.config = config
            self.clock = clock
            self.dwell = dwell
            self.continuation = continuation
        }
    }

    func end() {
        let c = lock.withLock { () -> AsyncStream<SampledFrame>.Continuation? in
            defer { continuation = nil; config = nil; dwell = nil }
            return continuation
        }
        c?.finish()
    }

    func handle(_ pixels: CVPixelBuffer) {
        let state = lock.withLock { (config, clock, dwell, continuation) }
        guard let config = state.0, let dwell = state.2, let continuation = state.3 else { return }
        let tMs = state.1.tripMs(atBufferTime: DetectionController.clockNow())
        let portrait = CVPixelBufferGetHeight(pixels) > CVPixelBufferGetWidth(pixels)
        let (w, h) = portrait ? (config.lumaHeight, config.lumaWidth) : (config.lumaWidth, config.lumaHeight)
        guard let jpeg = FrameSampler.jpeg(pixels, longEdge: config.jpegLongEdgePx, quality: config.jpegQuality) else { return }
        let luma = FrameSampler.luma(pixels, width: w, height: h)
        continuation.yield(SampledFrame(tMs: tMs, luma: luma, jpeg: jpeg, dwell: dwell()))
    }
}
