import Foundation

/// Tuning for the mount level from the bundled `level_config.json` (config, not code).
public struct LevelConfig: Codable, Sendable, Equatable {
    /// Both axes within this many degrees count as level.
    public var toleranceDeg: Double
    /// Once level, either axis beyond this many degrees counts as leaving it.
    public var leaveDeg: Double
    /// How long the phone must stay level and still before it counts.
    public var settleS: Double
    /// Rotation rate (rad/s) at or below which the phone counts as still.
    public var stillRadS: Double
    /// Gravity in the screen's plane below this (in g) means the phone lies flat and tilt is undefined.
    public var flatGravity: Double
    /// Degrees either axis moves between ticks.
    public var tickStepDeg: Double
    /// Shortest gap between two ticks.
    public var tickMinIntervalS: Double
    /// At this many degrees off level and beyond, ticks are at their weakest.
    public var tickFarDeg: Double
    /// Intensity (0...1) of the weakest tick.
    public var tickMinIntensity: Double
    /// Low-pass weight of each new gravity sample (1 = no smoothing).
    public var smoothing: Double
    /// Motion samples per second.
    public var updateHz: Double
    /// Degrees off level at which the bubble reaches the ring.
    public var bubbleRangeDeg: Double
    /// How long the level stays on screen after the phone is level.
    public var fadeDelayS: Double

    enum CodingKeys: String, CodingKey {
        case toleranceDeg = "tolerance_deg"
        case leaveDeg = "leave_deg"
        case settleS = "settle_s"
        case stillRadS = "still_rad_s"
        case flatGravity = "flat_gravity"
        case tickStepDeg = "tick_step_deg"
        case tickMinIntervalS = "tick_min_interval_s"
        case tickFarDeg = "tick_far_deg"
        case tickMinIntensity = "tick_min_intensity"
        case smoothing
        case updateHz = "update_hz"
        case bubbleRangeDeg = "bubble_range_deg"
        case fadeDelayS = "fade_delay_s"
    }

    public static func bundled() throws -> LevelConfig {
        try BundledResources.decode(LevelConfig.self, named: "level_config")
    }
}
