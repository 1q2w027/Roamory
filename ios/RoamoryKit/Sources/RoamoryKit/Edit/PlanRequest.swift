import Foundation

// Codable mirror of contracts/plan_request.schema.json. Nullable fields are required keys,
// so encoders write an explicit null instead of leaving the key out.

public enum MomentSource: String, Codable, Sendable {
    case ai, button
    case localFallback = "local_fallback"
}

public enum EventType: String, Codable, Sendable {
    case scenery, landmark, activity, food, social, other
}

public struct Destination: Codable, Sendable, Equatable {
    public var country: String
    public var city: String?

    public init(country: String, city: String?) {
        self.country = country
        self.city = city
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(country, forKey: .country)
        try c.encode(city, forKey: .city)
    }
}

public struct PlanRequest: Codable, Sendable, Equatable {
    public struct Clip: Codable, Sendable, Equatable {
        public var momentId: String
        /// Clip start on the trip clock; used for chronological order.
        public var tFromMs: Int
        public var tToMs: Int
        /// Length of clips/{moment_id}.mp4; trims must fall inside [0, durationS].
        public var durationS: Double
        public var source: MomentSource
        public var eventType: EventType?
        public var description: String?
        public var score: Double?
        public var proposedInS: Double
        public var proposedOutS: Double
        /// Seconds at the start of the clip file recorded below full frame rate; ramps must stay inside it.
        public var lowFpsLeadInS: Double
        public var thumbnailCount: Int

        public init(
            momentId: String, tFromMs: Int, tToMs: Int, durationS: Double, source: MomentSource,
            eventType: EventType?, description: String?, score: Double?,
            proposedInS: Double, proposedOutS: Double, lowFpsLeadInS: Double, thumbnailCount: Int
        ) {
            self.momentId = momentId
            self.tFromMs = tFromMs
            self.tToMs = tToMs
            self.durationS = durationS
            self.source = source
            self.eventType = eventType
            self.description = description
            self.score = score
            self.proposedInS = proposedInS
            self.proposedOutS = proposedOutS
            self.lowFpsLeadInS = lowFpsLeadInS
            self.thumbnailCount = thumbnailCount
        }

        enum CodingKeys: String, CodingKey {
            case momentId = "moment_id"
            case tFromMs = "t_from_ms"
            case tToMs = "t_to_ms"
            case durationS = "duration_s"
            case source
            case eventType = "event_type"
            case description, score
            case proposedInS = "proposed_in_s"
            case proposedOutS = "proposed_out_s"
            case lowFpsLeadInS = "low_fps_lead_in_s"
            case thumbnailCount = "thumbnail_count"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(momentId, forKey: .momentId)
            try c.encode(tFromMs, forKey: .tFromMs)
            try c.encode(tToMs, forKey: .tToMs)
            try c.encode(durationS, forKey: .durationS)
            try c.encode(source, forKey: .source)
            try c.encode(eventType, forKey: .eventType)
            try c.encode(description, forKey: .description)
            try c.encode(score, forKey: .score)
            try c.encode(proposedInS, forKey: .proposedInS)
            try c.encode(proposedOutS, forKey: .proposedOutS)
            try c.encode(lowFpsLeadInS, forKey: .lowFpsLeadInS)
            try c.encode(thumbnailCount, forKey: .thumbnailCount)
        }
    }

    public var tripId: String
    public var style: Style
    public var tripType: String
    public var destination: Destination
    /// Local start date, YYYY-MM-DD.
    public var startDate: String
    /// The preset's `target_s.default`.
    public var targetS: Double
    /// See `EffectiveTarget`.
    public var effectiveTargetS: Double
    public var clips: [Clip]

    public init(
        tripId: String, style: Style, tripType: String, destination: Destination, startDate: String,
        targetS: Double, effectiveTargetS: Double, clips: [Clip]
    ) {
        self.tripId = tripId
        self.style = style
        self.tripType = tripType
        self.destination = destination
        self.startDate = startDate
        self.targetS = targetS
        self.effectiveTargetS = effectiveTargetS
        self.clips = clips
    }

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case style
        case tripType = "trip_type"
        case destination
        case startDate = "start_date"
        case targetS = "target_s"
        case effectiveTargetS = "effective_target_s"
        case clips
    }
}
