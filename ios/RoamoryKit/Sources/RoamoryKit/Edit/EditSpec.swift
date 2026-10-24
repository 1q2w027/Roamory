import Foundation

// The planner's output and the renderer's input. Same shape as contracts/edit_spec.schema.json on `main`.

public struct EditSpec: Codable, Sendable, Equatable {
    public struct Title: Codable, Sendable, Equatable {
        public var text: String
        public var subtitle: String?
        /// Overlaid on the start of the first clip; adds no time.
        public var durationS: Double

        public init(text: String, subtitle: String?, durationS: Double) {
            self.text = text
            self.subtitle = subtitle
            self.durationS = durationS
        }

        enum CodingKeys: String, CodingKey {
            case text, subtitle
            case durationS = "duration_s"
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(subtitle, forKey: .subtitle)
            try c.encode(durationS, forKey: .durationS)
        }
    }

    /// Playback-rate ramp over the first `overS` source seconds of the trim. 4 is 4x fast, 1 is real time.
    public struct SpeedRamp: Codable, Sendable, Equatable {
        public var from: Double
        public var to: Double
        public var overS: Double

        public init(from: Double, to: Double, overS: Double) {
            self.from = from
            self.to = to
            self.overS = overS
        }

        enum CodingKeys: String, CodingKey {
            case from, to
            case overS = "over_s"
        }

        /// The 4 constant rates the ramp is split into.
        public var stepRates: [Double] { (0..<4).map { from + (to - from) * Double($0) / 3 } }
    }

    public struct Clip: Codable, Sendable, Equatable {
        /// The source clip's id; several spec clips can cut from the same file.
        public var momentId: String
        /// Seconds from the start of the clip file.
        public var inS: Double
        public var outS: Double
        /// On the first clip, fade/dissolve means from black and overlaps nothing.
        public var transitionIn: Transition
        /// 0 when `transitionIn` is cut; otherwise the overlap with the previous clip.
        public var transitionS: Double
        public var speedRamp: SpeedRamp?
        public var caption: String?

        public init(
            momentId: String, inS: Double, outS: Double, transitionIn: Transition, transitionS: Double,
            speedRamp: SpeedRamp?, caption: String?
        ) {
            self.momentId = momentId
            self.inS = inS
            self.outS = outS
            self.transitionIn = transitionIn
            self.transitionS = transitionS
            self.speedRamp = speedRamp
            self.caption = caption
        }

        enum CodingKeys: String, CodingKey {
            case momentId = "moment_id"
            case inS = "in_s"
            case outS = "out_s"
            case transitionIn = "transition_in"
            case transitionS = "transition_s"
            case speedRamp = "speed_ramp"
            case caption
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(momentId, forKey: .momentId)
            try c.encode(inS, forKey: .inS)
            try c.encode(outS, forKey: .outS)
            try c.encode(transitionIn, forKey: .transitionIn)
            try c.encode(transitionS, forKey: .transitionS)
            try c.encode(speedRamp, forKey: .speedRamp)
            try c.encode(caption, forKey: .caption)
        }

        /// Source seconds used (`out_s - in_s`).
        public var sourceLengthS: Double { outS - inS }
    }

    public struct Music: Codable, Sendable, Equatable {
        /// Bundled track id, normally the preset's `music_track`.
        public var track: String
        public var gainDb: Double
        /// True: original clip audio is muted under the music. False: it plays (Vlog).
        public var duckOriginalAudio: Bool

        public init(track: String, gainDb: Double, duckOriginalAudio: Bool) {
            self.track = track
            self.gainDb = gainDb
            self.duckOriginalAudio = duckOriginalAudio
        }

        enum CodingKeys: String, CodingKey {
            case track
            case gainDb = "gain_db"
            case duckOriginalAudio = "duck_original_audio"
        }
    }

    /// Plays after the last clip, after a hard cut, and adds `durationS`.
    public struct EndCard: Codable, Sendable, Equatable {
        public var text: String
        public var durationS: Double

        public init(text: String, durationS: Double) {
            self.text = text
            self.durationS = durationS
        }

        enum CodingKeys: String, CodingKey {
            case text
            case durationS = "duration_s"
        }
    }

    public var tripId: String
    public var style: Style
    public var output: OutputFormat
    public var title: Title
    /// In playback order.
    public var clips: [Clip]
    public var music: Music
    public var endCard: EndCard

    public init(
        tripId: String, style: Style, output: OutputFormat, title: Title, clips: [Clip], music: Music,
        endCard: EndCard
    ) {
        self.tripId = tripId
        self.style = style
        self.output = output
        self.title = title
        self.clips = clips
        self.music = music
        self.endCard = endCard
    }

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case style, output, title, clips, music
        case endCard = "end_card"
    }

    /// The same spec with every transition a hard cut (the renderer's retry).
    public func withHardCuts() -> EditSpec {
        var spec = self
        spec.clips = clips.map { clip in
            var clip = clip
            clip.transitionIn = .cut
            clip.transitionS = 0
            return clip
        }
        return spec
    }
}
