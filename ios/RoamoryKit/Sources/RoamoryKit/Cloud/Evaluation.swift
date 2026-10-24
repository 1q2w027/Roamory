import Foundation

// Codable mirror of contracts/evaluation.schema.json, the 200 response of POST /v1/evaluate.

public struct Evaluation: Codable, Sendable, Equatable {
    public enum Tier: String, Codable, Sendable {
        case fast = "2a"
        case strong = "2b"
    }

    public enum SaveDecision: String, Codable, Sendable {
        case save, skip, uncertain
    }

    public struct WindowHint: Codable, Sendable, Equatable {
        public var pre: Int
        public var post: Int

        public init(pre: Int, post: Int) {
            self.pre = pre
            self.post = post
        }
    }

    /// The model's answer (TRD 8.2), already clamped by the server.
    public struct Verdict: Codable, Sendable, Equatable {
        public var eventType: EventType
        public var matchedPreferences: [String]
        public var preferenceAlignment: Double
        public var visualInterest: Double
        public var significance: Double
        public var visualQuality: Double
        public var saveDecision: SaveDecision
        public var bestFrameIndex: Int
        public var windowHintS: WindowHint
        public var description: String
        public var reason: String

        enum CodingKeys: String, CodingKey {
            case eventType = "event_type"
            case matchedPreferences = "matched_preferences"
            case preferenceAlignment = "preference_alignment"
            case visualInterest = "visual_interest"
            case significance
            case visualQuality = "visual_quality"
            case saveDecision = "save_decision"
            case bestFrameIndex = "best_frame_index"
            case windowHintS = "window_hint_s"
            case description, reason
        }
    }

    public var version: Int
    /// The server's decision; false releases the speculative hold.
    public var keep: Bool
    public var s2: Double
    public var tier: Tier
    public var latencyMs: Int
    public var verdict: Verdict

    enum CodingKeys: String, CodingKey {
        case version, keep, s2, tier
        case latencyMs = "latency_ms"
        case verdict
    }
}
