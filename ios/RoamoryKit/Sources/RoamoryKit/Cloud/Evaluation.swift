import Foundation

// Codable mirror of contracts/evaluation.schema.json, the 200 response of POST /v1/evaluate.

public struct Evaluation: Codable, Sendable, Equatable {
    public enum SaveDecision: String, Codable, Sendable {
        case save, skip
    }

    public struct WindowHint: Codable, Sendable, Equatable {
        public var pre: Int
        public var post: Int

        public init(pre: Int, post: Int) {
            self.pre = pre
            self.post = post
        }
    }

    /// The model's answer (TRD 8.2), already cleaned up by the server. The model decides; it gives no scores.
    public struct Verdict: Codable, Sendable, Equatable {
        public var eventType: EventType
        public var matchedPreferences: [String]
        public var saveDecision: SaveDecision
        public var bestFrameIndex: Int
        public var windowHintS: WindowHint
        public var description: String
        public var reason: String

        enum CodingKeys: String, CodingKey {
            case eventType = "event_type"
            case matchedPreferences = "matched_preferences"
            case saveDecision = "save_decision"
            case bestFrameIndex = "best_frame_index"
            case windowHintS = "window_hint_s"
            case description, reason
        }
    }

    public var version: Int
    /// The server's decision; false releases the speculative hold.
    public var keep: Bool
    public var latencyMs: Int
    public var verdict: Verdict

    enum CodingKeys: String, CodingKey {
        case version, keep
        case latencyMs = "latency_ms"
        case verdict
    }
}
