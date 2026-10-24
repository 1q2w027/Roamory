import Foundation

/// Moment-record fields that can change after the clip finalizes, so they live outside the sidecar (TRD 3.3).
/// Stored as `moments/{momentId}.json` in the trip folder (`TripFolder`).
public struct MomentFields: Codable, Sendable, Equatable {
    public var eventType: EventType?
    public var description: String?
    public var score: Double?
    /// The Moment record's `bestFrameDhash`; nil derives it from the sharpest sidecar sample.
    public var bestFrameDhash: UInt64?

    public init(eventType: EventType? = nil, description: String? = nil, score: Double? = nil, bestFrameDhash: UInt64? = nil) {
        self.eventType = eventType
        self.description = description
        self.score = score
        self.bestFrameDhash = bestFrameDhash
    }

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case description, score
        case bestFrameDhash = "best_frame_dhash"
    }
}

/// One finalized clip, the input to editing: the Moment record plus the clip file's sidecar.
public struct ClipInfo: Sendable, Equatable, Identifiable {
    public var momentId: String
    public var source: MomentSource
    public var eventType: EventType?
    public var description: String?
    public var score: Double?
    /// Trip-clock span of the clip file.
    public var fromMs: Int
    public var toMs: Int
    /// The trigger, in seconds from the clip file's start.
    public var triggerS: Double
    public var bestFrameDhash: UInt64?
    public var clipURL: URL
    public var durationS: Double
    public var fpsProfile: [ClipSidecar.FpsStep]
    public var hasAudio: Bool
    public var samples: [ClipSidecar.Sample]
    /// Best sub-window, set by `PrePass`; the whole clip until then.
    public var proposedInS: Double
    public var proposedOutS: Double

    public var id: String { momentId }
    public var isButton: Bool { source == .button }

    public init(
        momentId: String, source: MomentSource, eventType: EventType? = nil, description: String? = nil,
        score: Double? = nil, fromMs: Int, toMs: Int, triggerS: Double, bestFrameDhash: UInt64? = nil,
        clipURL: URL, durationS: Double, fpsProfile: [ClipSidecar.FpsStep] = [.init(tS: 0, fps: 30)],
        hasAudio: Bool = false, samples: [ClipSidecar.Sample] = []
    ) {
        self.momentId = momentId
        self.source = source
        self.eventType = eventType
        self.description = description
        self.score = score
        self.fromMs = fromMs
        self.toMs = toMs
        self.triggerS = triggerS
        self.bestFrameDhash = bestFrameDhash
        self.clipURL = clipURL
        self.durationS = durationS
        self.fpsProfile = fpsProfile
        self.hasAudio = hasAudio
        self.samples = samples
        self.proposedInS = 0
        self.proposedOutS = durationS
    }

    /// - Parameter tripFolder: the folder the sidecar's `clip_path` is relative to.
    public init(sidecar: ClipSidecar, moment: MomentFields, tripFolder: URL) {
        let sharpest = sidecar.samples.max { $0.sharpness < $1.sharpness }
        self.init(
            momentId: sidecar.momentId, source: sidecar.source, eventType: moment.eventType,
            description: moment.description, score: moment.score, fromMs: sidecar.fromMs, toMs: sidecar.toMs,
            triggerS: Double(sidecar.triggerMs - sidecar.fromMs) / 1000,
            bestFrameDhash: moment.bestFrameDhash ?? sharpest.flatMap { UInt64($0.dhash, radix: 16) },
            clipURL: tripFolder.appending(path: sidecar.clipPath), durationS: sidecar.durationS,
            fpsProfile: sidecar.fpsProfile, hasAudio: sidecar.hasAudio, samples: sidecar.samples
        )
    }

    /// Seconds at the start of the file recorded below `fullFpsMin` (TRD 4.3); a speed ramp must stay inside it.
    public func lowFpsLeadInS(fullFpsMin: Double) -> Double {
        let firstFull = fpsProfile.first { $0.fps >= fullFpsMin }
        return min(firstFull?.tS ?? durationS, durationS)
    }
}

/// Trip facts the planner may use for titles and captions (PRD FR-015).
public struct TripContext: Sendable, Equatable {
    public var tripId: String
    public var style: Style
    public var tripType: String
    public var destination: Destination
    /// Local start date, YYYY-MM-DD.
    public var startDate: String
    /// Off: no plan request leaves the phone; the fallback planner runs.
    public var allowCloudAnalysis: Bool

    public init(tripId: String, style: Style, tripType: String, destination: Destination, startDate: String, allowCloudAnalysis: Bool) {
        self.tripId = tripId
        self.style = style
        self.tripType = tripType
        self.destination = destination
        self.startDate = startDate
        self.allowCloudAnalysis = allowCloudAnalysis
    }
}

extension PlanRequest {
    /// The request for these clips; `thumbnailCounts` is how many thumbnails will be sent per moment id.
    public init(trip: TripContext, clips: [ClipInfo], preset: StylePreset, config: EditConfig, thumbnailCounts: [String: Int] = [:]) {
        self.init(
            tripId: trip.tripId, style: trip.style, tripType: trip.tripType, destination: trip.destination,
            startDate: trip.startDate, targetS: preset.targetS.default,
            effectiveTargetS: EffectiveTarget.seconds(buttonCount: clips.count(where: \.isButton), preset: preset),
            clips: clips.map { clip in
                Clip(
                    momentId: clip.momentId, tFromMs: clip.fromMs, tToMs: clip.toMs, durationS: clip.durationS,
                    source: clip.source, eventType: clip.eventType, description: clip.description, score: clip.score,
                    proposedInS: clip.proposedInS, proposedOutS: clip.proposedOutS,
                    lowFpsLeadInS: clip.lowFpsLeadInS(fullFpsMin: config.fullFpsMin),
                    thumbnailCount: thumbnailCounts[clip.momentId] ?? 0
                )
            }
        )
    }
}
