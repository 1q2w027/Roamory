import Foundation

/// Codable mirror of contracts/clip_sidecar.schema.json: `clips/{moment_id}.json`, written by Buffer, read by Edit.
public struct ClipSidecar: Codable, Sendable, Equatable {
    public struct FpsStep: Codable, Sendable, Equatable {
        /// Seconds from the clip file's start.
        public var tS: Double
        public var fps: Double

        public init(tS: Double, fps: Double) {
            self.tS = tS
            self.fps = fps
        }

        enum CodingKeys: String, CodingKey {
            case tS = "t_s"
            case fps
        }
    }

    /// A Stage 1 sample (TRD 6) inside the clip.
    public struct Sample: Codable, Sendable, Equatable {
        public var tS: Double
        public var sharpness: Double
        public var change: Double
        /// 64-bit difference hash as 16 lowercase hex digits.
        public var dhash: String

        public init(tS: Double, sharpness: Double, change: Double, dhash: String) {
            self.tS = tS
            self.sharpness = sharpness
            self.change = change
            self.dhash = dhash
        }

        enum CodingKeys: String, CodingKey {
            case tS = "t_s"
            case sharpness, change, dhash
        }
    }

    public var version: Int
    public var momentId: String
    public var tripId: String
    public var sessionId: String
    public var source: MomentSource
    /// Trip clock.
    public var triggerMs: Int
    /// Trip-clock time of the clip file's first frame.
    public var fromMs: Int
    public var toMs: Int
    /// Relative to the trip folder, e.g. clips/m_07.mp4.
    public var clipPath: String
    public var durationS: Double
    public var hasAudio: Bool
    /// Frame-rate changes, sorted by `tS`; the first has `tS` = 0.
    public var fpsProfile: [FpsStep]
    public var samples: [Sample]

    enum CodingKeys: String, CodingKey {
        case version
        case momentId = "moment_id"
        case tripId = "trip_id"
        case sessionId = "session_id"
        case source
        case triggerMs = "trigger_ms"
        case fromMs = "from_ms"
        case toMs = "to_ms"
        case clipPath = "clip_path"
        case durationS = "duration_s"
        case hasAudio = "has_audio"
        case fpsProfile = "fps_profile"
        case samples
    }
}
