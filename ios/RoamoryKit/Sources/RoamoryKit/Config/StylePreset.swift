import Foundation

// Codable mirror of contracts/style_presets.schema.json. The schema is the source of truth.

public enum Style: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case cinematic, reels, documentary, vlog
}

public enum Transition: String, Codable, Sendable {
    case cut, fade, dissolve
}

public struct ValueRange: Codable, Sendable, Equatable {
    public var min: Double
    public var max: Double
    public var `default`: Double

    public init(min: Double, max: Double, default: Double) {
        self.min = min
        self.max = max
        self.default = `default`
    }
}

public struct OutputFormat: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var fps: Int

    public init(width: Int, height: Int, fps: Int) {
        self.width = width
        self.height = height
        self.fps = fps
    }

    public var isPortrait: Bool { height > width }
}

public struct StylePreset: Codable, Sendable, Equatable {
    public enum Aspect: String, Codable, Sendable {
        case landscape = "16:9"
        case portrait = "9:16"
    }

    /// Video length; `default` is what the plan request's `target_s` carries.
    public var targetS: ValueRange
    /// Per-clip source length (`out_s - in_s`); `default` is the fallback planner's length.
    public var clipS: ValueRange
    public var transition: Transition
    public var transitionS: ValueRange
    public var aspect: Aspect
    public var output: OutputFormat
    public var titleS: Double
    public var endCardS: Double
    public var musicTrack: String
    public var musicGainDb: Double
    /// True keeps the clips' own sound in the video.
    public var keepOriginalAudio: Bool
    public var captions: Bool
    public var allowSpeedRamp: Bool

    enum CodingKeys: String, CodingKey {
        case targetS = "target_s"
        case clipS = "clip_s"
        case transition
        case transitionS = "transition_s"
        case aspect, output
        case titleS = "title_s"
        case endCardS = "end_card_s"
        case musicTrack = "music_track"
        case musicGainDb = "music_gain_db"
        case keepOriginalAudio = "keep_original_audio"
        case captions
        case allowSpeedRamp = "allow_speed_ramp"
    }
}

public struct StylePresets: Codable, Sendable, Equatable {
    public var version: Int
    public var presets: [Style: StylePreset]

    public subscript(style: Style) -> StylePreset {
        guard let preset = presets[style] else { preconditionFailure("style_presets.json has no \(style) preset") }
        return preset
    }

    /// The copy of contracts/style_presets.json in the bundle (`scripts/sync-contracts.sh`).
    public static func bundled() throws -> StylePresets {
        try BundledResources.decode(StylePresets.self, named: "style_presets")
    }
}
