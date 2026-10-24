import Foundation

/// The rolling buffer's side of detection (TRD 5.3). The buffer implements it; the detector never touches footage.
///
/// The detector mints every moment id, unique per call. If the buffer merges overlapping moments (TRD 5.3 rule 4),
/// it does so internally and keeps each id's protection separate: releasing one id never drops footage another id
/// still protects. When a moment's window closes, the buffer asks `MomentDetector.finalDecision(for:)`.
/// `release` can arrive before that, and the final decision may then also be `.release`; treat both as idempotent.
public protocol MomentHolder: Sendable {
    /// Protect [triggerMs − pre, triggerMs + post] now under `momentId`.
    func hold(momentId: String, triggerMs: Int, source: MomentSource) async
    /// The cloud said skip: drop this id's protection (the footage then ages out of the buffer).
    func release(_ momentId: String) async
}

/// Trip fields every evaluate request carries.
public struct TripInfo: Sendable {
    public var tripId: String
    public var installId: String
    public var style: Style
    public var tripType: String
    public var destination: EvaluateContext.Destination
    public var lengthDays: Int

    public init(tripId: String, installId: String, style: Style, tripType: String,
                destination: EvaluateContext.Destination, lengthDays: Int) {
        self.tripId = tripId
        self.installId = installId
        self.style = style
        self.tripType = tripType
        self.destination = destination
        self.lengthDays = lengthDays
    }
}

/// One sampled frame (about every 2 s) from the camera or a replayed video.
public struct SampledFrame: Sendable {
    /// Trip clock.
    public var tMs: Int
    /// Small grayscale copy for the signals (`FrameSampler.luma`).
    public var luma: LumaFrame
    /// 512 px JPEG sent to the cloud (`FrameSampler.jpeg`).
    public var jpeg: Data
    /// 0…1 from motion sensors; 1 when the wearer has stopped.
    public var dwell: Double

    public init(tMs: Int, luma: LumaFrame, jpeg: Data, dwell: Double) {
        self.tMs = tMs
        self.luma = luma
        self.jpeg = jpeg
        self.dwell = dwell
    }
}

/// What the buffer does with a moment when its window closes.
public enum MomentDecision: Sendable, Equatable {
    case keep(source: MomentSource, eventType: EventType?, description: String?, score: Double?)
    case release
}

/// Stage 1 on the phone (TRD 6): signals → local score → gate → hold → evaluate → keep or release.
/// Recording never waits on it: holds are placed before any request, and requests run in child tasks.
/// Call `ingest` from one task, awaiting each call in order; the peak and change logic depend on sample order.
public actor MomentDetector {
    private enum Status {
        case pending
        case kept(eventType: EventType?, description: String?, score: Double?)
        case released
    }

    private struct Moment {
        var source: MomentSource
        var l: Double
        var status: Status
        var finalized = false
    }

    private struct Sample {
        var tMs: Int
        var jpeg: Data
        var signals: FrameSignals
        var score: LocalScore
        /// Mean of the last 3 change values at this sample.
        var motion: Double
    }

    private struct Job {
        var momentId: String
        var context: EvaluateContext
        var frames: [Data]
    }

    let trip: TripInfo
    let config: DetectionConfig
    let holder: MomentHolder
    let evaluator: Evaluating?
    let cloudAllowed: Bool

    private var scorer: LocalScorer
    private var gate: EscalationGate
    private var samples: [Sample] = []  // current session only, newest last
    private var previousLuma: LumaFrame?
    private var recentChanges: [Double] = []
    private var recentEscalated: [UInt64] = []
    private var recentDescriptions: [String] = []  // every kept moment this trip, newest first
    private var moments: [String: Moment] = [:]
    private var selectQueue: [Job] = []
    private var describeQueue: [Job] = []
    private var inFlight = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let momentIdPrefix: String
    private var momentCount = 0

    private static let samplesKept = 4
    private static let recentEscalatedKept = 5

    /// - Parameter cloudAllowed: the user's "Allow cloud analysis" setting. Off (or no evaluator), candidates are
    ///   still held and settled by the local fallback when they finalize; no request is sent.
    /// - Parameter momentIdPrefix: ids are `{prefix}_{n}`; the default random prefix keeps ids unique across app runs.
    public init(trip: TripInfo, config: DetectionConfig, holder: MomentHolder, evaluator: Evaluating?,
                cloudAllowed: Bool, demoMode: Bool = false,
                momentIdPrefix: String = "m\(UUID().uuidString.prefix(6).lowercased())") {
        self.momentIdPrefix = momentIdPrefix
        self.trip = trip
        self.config = config
        self.holder = holder
        self.evaluator = evaluator
        self.cloudAllowed = cloudAllowed
        self.scorer = LocalScorer(config: config)
        self.gate = EscalationGate(config: config, demoMode: demoMode)
    }

    private var canSend: Bool { cloudAllowed && evaluator != nil }

    /// A new recording session: frames and signal history from the last one never mix with this one.
    public func sessionStarted() {
        scorer.reset()
        gate.reset()
        samples.removeAll()
        previousLuma = nil
        recentChanges.removeAll()
    }

    public func ingest(_ frame: SampledFrame) async {
        let signals = FrameSignals.compute(frame.luma, previous: previousLuma)
        previousLuma = frame.luma
        recentChanges = Array((recentChanges + [signals.change]).suffix(3))
        let score = scorer.score(signals, dwell: frame.dwell, recentEscalated: recentEscalated)
        let motion = recentChanges.reduce(0, +) / Double(recentChanges.count)
        samples = Array((samples + [Sample(tMs: frame.tMs, jpeg: frame.jpeg, signals: signals, score: score, motion: motion)])
            .suffix(Self.samplesKept))

        // The gate always runs; whether a request goes out is decided in `escalate`.
        guard let e = gate.push(tMs: frame.tMs, l: score.l, dhash: signals.dhash, cloudAllowed: true) else { return }
        recentEscalated = Array((recentEscalated + [e.dhash]).suffix(Self.recentEscalatedKept))
        let novelty = samples.first { $0.tMs == e.tMs }?.score.novelty ?? score.novelty
        await escalate(e, novelty: novelty, frames: framesEnding(at: e.tMs))
    }

    private func newMomentId() -> String {
        momentCount += 1
        return "\(momentIdPrefix)_\(momentCount)"
    }

    /// Hold first, then queue the select request (TRD 6, speculative hold).
    func escalate(_ e: Escalation, novelty: Double, frames: [Data]) async {
        // Register and read state before the await: other calls can run on the actor while the buffer holds.
        let id = newMomentId()
        moments[id] = Moment(source: .ai, l: e.l, status: .pending)
        let sample = samples.first { $0.tMs == e.tMs }
        await holder.hold(momentId: id, triggerMs: e.tMs, source: .ai)
        guard canSend, !frames.isEmpty, moments[id]?.finalized == false else { return }
        selectQueue.append(Job(momentId: id, context: context(.select, tMs: e.tMs, l: e.l, novelty: novelty,
                                                              sample: sample, forced: e.forced), frames: frames))
        if selectQueue.count > config.maxQueued {
            selectQueue.removeFirst()  // its moment stays pending and the local fallback settles it
        }
        pump()
    }

    /// A button moment is always kept (TRD 7); the cloud is asked only for a description, after any select work.
    public func buttonPressed(atMs: Int) async -> String {
        let id = newMomentId()
        moments[id] = Moment(source: .button, l: 0, status: .pending)
        let frames = framesEnding(at: atMs)
        let last = samples.last(where: { $0.tMs <= atMs })
        await holder.hold(momentId: id, triggerMs: atMs, source: .button)
        guard canSend, !frames.isEmpty, let last, moments[id]?.finalized == false else { return id }
        describeQueue.append(Job(momentId: id, context: context(.describe, tMs: last.tMs, l: last.score.l,
                                                                novelty: last.score.novelty, sample: last, forced: false),
                                 frames: frames))
        pump()
        return id
    }

    /// Called by the buffer when the moment's window closes (TRD 5.3 step 3). Final: later answers are ignored.
    /// An id this detector never minted is released.
    public func finalDecision(for momentId: String) -> MomentDecision {
        guard var m = moments[momentId] else { return .release }
        m.finalized = true
        moments[momentId] = m
        selectQueue.removeAll { $0.momentId == momentId }
        describeQueue.removeAll { $0.momentId == momentId }
        notifyIfIdle()

        switch (m.source, m.status) {
        case (.button, .kept(let eventType, let description, let score)):
            return .keep(source: .button, eventType: eventType, description: description, score: score)
        case (.button, _):
            return .keep(source: .button, eventType: nil, description: nil, score: nil)
        case (_, .kept(let eventType, let description, let score)):
            return .keep(source: .ai, eventType: eventType, description: description, score: score)
        case (_, .released):
            return .release
        case (_, .pending):
            return m.l >= config.localFallbackMin
                ? .keep(source: .localFallback, eventType: nil, description: nil, score: m.l) : .release
        }
    }

    /// Returns when no request is queued or in flight. For tests and the replay tool.
    public func waitForIdle() async {
        if isIdle { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: - Requests

    private var isIdle: Bool { inFlight == 0 && selectQueue.isEmpty && describeQueue.isEmpty }

    private func notifyIfIdle() {
        guard isIdle else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func pump() {
        guard let evaluator else { return }
        while inFlight < config.maxInFlight {
            let job: Job
            if !selectQueue.isEmpty {
                job = selectQueue.removeFirst()
            } else if !describeQueue.isEmpty {
                job = describeQueue.removeFirst()
            } else {
                break
            }
            inFlight += 1
            Task {
                let result: Result<Evaluation, Error>
                do {
                    result = .success(try await evaluator.evaluate(context: job.context, frames: job.frames))
                } catch {
                    result = .failure(error)
                }
                await self.finish(job, result)
            }
        }
    }

    private func finish(_ job: Job, _ result: Result<Evaluation, Error>) async {
        defer {
            inFlight -= 1
            pump()
            notifyIfIdle()
        }
        // An error leaves the moment pending; so does an answer that arrives after the buffer finalized it.
        guard case .success(let evaluation) = result, var m = moments[job.momentId], !m.finalized else { return }
        let verdict = evaluation.verdict
        if evaluation.keep || m.source == .button {
            // The model gives no score, so ai clips rank by their local score L; button moments have none.
            m.status = .kept(eventType: verdict.eventType, description: verdict.description,
                             score: m.source == .button ? nil : m.l)
            moments[job.momentId] = m
            recentDescriptions.insert(verdict.description, at: 0)
        } else {
            m.status = .released
            moments[job.momentId] = m
            await holder.release(job.momentId)
        }
    }

    // MARK: - Helpers

    /// Up to `framesPerRequest` JPEGs of this session, oldest first, ending at the sample at or before `tMs`.
    private func framesEnding(at tMs: Int) -> [Data] {
        Array(samples.filter { $0.tMs <= tMs }.suffix(config.framesPerRequest).map(\.jpeg))
    }

    private func context(_ purpose: EvaluateContext.Purpose, tMs: Int, l: Double, novelty: Double,
                         sample: Sample?, forced: Bool) -> EvaluateContext {
        EvaluateContext(
            tripId: trip.tripId, installId: trip.installId, purpose: purpose, sampleTMs: tMs, style: trip.style,
            tripType: trip.tripType, destination: trip.destination, lengthDays: trip.lengthDays,
            local: .init(score: clamp(l), novelty: clamp(novelty), sharpness: sample?.signals.sharpness ?? 0,
                         change: sample?.signals.change ?? 0, motion: sample?.motion ?? 0, forced: forced),
            recentDescriptions: recentDescriptions
        )
    }
}
