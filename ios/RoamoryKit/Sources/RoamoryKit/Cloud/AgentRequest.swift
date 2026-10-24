import Foundation

/// Codable mirror of contracts/agent_request.schema.json: the `request` part of `POST /v1/agent`.
public struct AgentRequest: Codable, Sendable, Equatable {
    /// One uploaded whole clip; the plan request's clip fields, minus thumbnails, plus `has_audio`.
    public struct Clip: Codable, Sendable, Equatable {
        public var momentId: String
        public var source: MomentSource
        public var eventType: EventType?
        public var description: String?
        public var score: Double?
        public var tFromMs: Int
        /// Of the uploaded file (`rebased`).
        public var durationS: Double
        public var hasAudio: Bool
        public var proposedInS: Double
        public var proposedOutS: Double
        public var lowFpsLeadInS: Double

        public init(
            momentId: String, source: MomentSource, eventType: EventType?, description: String?, score: Double?, tFromMs: Int,
            durationS: Double, hasAudio: Bool, proposedInS: Double, proposedOutS: Double, lowFpsLeadInS: Double
        ) {
            self.momentId = momentId
            self.source = source
            self.eventType = eventType
            self.description = description
            self.score = score
            self.tFromMs = tFromMs
            self.durationS = durationS
            self.hasAudio = hasAudio
            self.proposedInS = proposedInS
            self.proposedOutS = proposedOutS
            self.lowFpsLeadInS = lowFpsLeadInS
        }

        enum CodingKeys: String, CodingKey {
            case momentId = "moment_id"
            case source
            case eventType = "event_type"
            case description, score
            case tFromMs = "t_from_ms"
            case durationS = "duration_s"
            case hasAudio = "has_audio"
            case proposedInS = "proposed_in_s"
            case proposedOutS = "proposed_out_s"
            case lowFpsLeadInS = "low_fps_lead_in_s"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(momentId, forKey: .momentId)
            try c.encode(source, forKey: .source)
            try c.encode(eventType, forKey: .eventType)
            try c.encode(description, forKey: .description)
            try c.encode(score, forKey: .score)
            try c.encode(tFromMs, forKey: .tFromMs)
            try c.encode(durationS, forKey: .durationS)
            try c.encode(hasAudio, forKey: .hasAudio)
            try c.encode(proposedInS, forKey: .proposedInS)
            try c.encode(proposedOutS, forKey: .proposedOutS)
            try c.encode(lowFpsLeadInS, forKey: .lowFpsLeadInS)
        }
    }

    public var tripId: String
    public var style: Style
    /// The preset's `target_s.default`.
    public var targetS: Double
    /// See `EffectiveTarget`.
    public var effectiveTargetS: Double
    public var context: RenderRequest.Context
    public var clips: [Clip]

    public init(tripId: String, style: Style, targetS: Double, effectiveTargetS: Double, context: RenderRequest.Context, clips: [Clip]) {
        self.tripId = tripId
        self.style = style
        self.targetS = targetS
        self.effectiveTargetS = effectiveTargetS
        self.context = context
        self.clips = clips
    }

    /// Every candidate clip after the pre-pass, with the durations of the files on the phone; the client
    /// rebases them onto the uploaded files.
    public init(trip: TripContext, clips: [ClipInfo], preset: StylePreset, config: EditConfig) {
        self.init(
            tripId: trip.tripId, style: trip.style, targetS: preset.targetS.default,
            effectiveTargetS: EffectiveTarget.seconds(buttonCount: clips.count(where: \.isButton), preset: preset),
            context: RenderRequest.Context(trip: trip),
            clips: clips.map { clip in
                Clip(
                    momentId: clip.momentId, source: clip.source, eventType: clip.eventType, description: clip.description,
                    score: clip.score, tFromMs: clip.fromMs, durationS: clip.durationS, hasAudio: clip.hasAudio,
                    proposedInS: clip.proposedInS, proposedOutS: clip.proposedOutS,
                    lowFpsLeadInS: clip.lowFpsLeadInS(fullFpsMin: config.fullFpsMin)
                )
            }
        )
    }

    /// Onto the re-encoded files (agent request rule 2): their duration and audio, and the proposed window
    /// kept inside the file, shifted earlier rather than shortened if the export came out short.
    public func rebased(_ uploaded: [RenderRequest.Clip]) -> AgentRequest {
        let byId = Dictionary(uploaded.map { ($0.momentId, $0) }, uniquingKeysWith: { first, _ in first })
        var rebased = self
        for i in rebased.clips.indices {
            guard let file = byId[rebased.clips[i].momentId] else { continue }
            let clip = rebased.clips[i]
            let length = clip.proposedOutS - clip.proposedInS
            let outS = min(clip.proposedOutS, file.durationS)
            rebased.clips[i].durationS = file.durationS
            rebased.clips[i].hasAudio = file.hasAudio
            rebased.clips[i].proposedOutS = outS
            rebased.clips[i].proposedInS = max(0, min(clip.proposedInS, outS - length))
            rebased.clips[i].lowFpsLeadInS = min(clip.lowFpsLeadInS, file.durationS)
        }
        return rebased
    }

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case style
        case targetS = "target_s"
        case effectiveTargetS = "effective_target_s"
        case context, clips
    }
}

/// Codable mirror of contracts/agent_result.schema.json: the body of `GET /v1/agent/{job_id}/result`.
public struct AgentResult: Codable, Sendable, Equatable {
    public struct Title: Codable, Sendable, Equatable {
        public var text: String
        public var subtitle: String?

        public init(text: String, subtitle: String?) {
            self.text = text
            self.subtitle = subtitle
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(subtitle, forKey: .subtitle)
        }
    }

    /// Where a clip is on screen, output seconds; transitions may overlap.
    public struct Moment: Codable, Sendable, Equatable {
        public var momentId: String
        public var startS: Double
        public var endS: Double

        public init(momentId: String, startS: Double, endS: Double) {
            self.momentId = momentId
            self.startS = startS
            self.endS = endS
        }

        enum CodingKeys: String, CodingKey {
            case momentId = "moment_id"
            case startS = "start_s"
            case endS = "end_s"
        }
    }

    public var totalS: Double
    public var title: Title
    /// In playback order.
    public var moments: [Moment]

    public init(totalS: Double, title: Title, moments: [Moment]) {
        self.totalS = totalS
        self.title = title
        self.moments = moments
    }

    enum CodingKeys: String, CodingKey {
        case totalS = "total_s"
        case title, moments
    }
}
