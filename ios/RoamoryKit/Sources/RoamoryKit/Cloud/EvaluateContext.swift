import Foundation

// Codable mirror of contracts/evaluate_context.schema.json, the `context` part of POST /v1/evaluate.

public struct EvaluateContext: Codable, Sendable, Equatable {
    public enum Purpose: String, Codable, Sendable {
        /// A Stage 1 candidate: the server decides keep or skip.
        case select
        /// A button moment, already kept: the server only describes it.
        case describe
    }

    public struct Destination: Codable, Sendable, Equatable {
        public var continent: String?
        public var country: String
        public var city: String?

        public init(continent: String?, country: String, city: String?) {
            self.continent = continent
            self.country = country
            self.city = city
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(continent, forKey: .continent)
            try c.encode(country, forKey: .country)
            try c.encode(city, forKey: .city)
        }
    }

    /// Stage 1 signals for the request's last frame (TRD 6).
    public struct LocalSignals: Codable, Sendable, Equatable {
        /// Local score L.
        public var score: Double
        public var novelty: Double
        public var sharpness: Double
        public var change: Double
        public var motion: Double
        public var forced: Bool

        public init(score: Double, novelty: Double, sharpness: Double, change: Double, motion: Double, forced: Bool) {
            self.score = score
            self.novelty = novelty
            self.sharpness = sharpness
            self.change = change
            self.motion = motion
            self.forced = forced
        }
    }

    public var version: Int
    public var tripId: String
    public var installId: String
    public var purpose: Purpose
    /// Trip-clock time of the last frame.
    public var sampleTMs: Int
    public var style: Style
    public var tripType: String
    public var destination: Destination
    public var lengthDays: Int
    public var local: LocalSignals
    /// Newest first, at most 5.
    public var recentDescriptions: [String]

    public init(
        tripId: String, installId: String, purpose: Purpose, sampleTMs: Int, style: Style, tripType: String,
        destination: Destination, lengthDays: Int, local: LocalSignals, recentDescriptions: [String]
    ) {
        self.version = 1
        self.tripId = tripId
        self.installId = installId
        self.purpose = purpose
        self.sampleTMs = sampleTMs
        self.style = style
        self.tripType = tripType
        self.destination = destination
        self.lengthDays = lengthDays
        self.local = local
        self.recentDescriptions = recentDescriptions
    }

    enum CodingKeys: String, CodingKey {
        case version
        case tripId = "trip_id"
        case installId = "install_id"
        case purpose
        case sampleTMs = "sample_t_ms"
        case style
        case tripType = "trip_type"
        case destination
        case lengthDays = "length_days"
        case local
        case recentDescriptions = "recent_descriptions"
    }
}
