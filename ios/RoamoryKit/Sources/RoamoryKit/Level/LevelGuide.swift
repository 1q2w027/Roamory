import Foundation

public enum LevelEvent: Equatable, Sendable {
    case reached, left
}

/// Tells when the phone has been level and still long enough to count, and when it leaves level again.
/// Passing through level while the phone is still moving (being clipped into the mount) does not count.
public struct LevelDetector: Sendable {
    private let config: LevelConfig
    public private(set) var isLevel = false
    /// When the current run of level, still samples started.
    private var since: TimeInterval?

    public init(config: LevelConfig) { self.config = config }

    /// One sample, angles in degrees and the rotation rate in rad/s. `.reached` fires once per stay at level.
    public mutating func update(tilt: Double, aim: Double, rotationRate: Double, at time: TimeInterval) -> LevelEvent? {
        if isLevel {
            guard abs(tilt) > config.leaveDeg || abs(aim) > config.aimLeaveDeg else { return nil }
            isLevel = false
            since = nil
            return .left
        }
        guard abs(tilt) <= config.toleranceDeg, abs(aim) <= config.aimToleranceDeg,
              rotationRate <= config.stillRadS else {
            since = nil
            return nil
        }
        let start = since ?? time
        since = start
        guard time - start >= config.settleS else { return nil }
        isLevel = true
        return .reached
    }

    /// The pose can no longer be measured (the phone is turned the wrong way): `.left` if it was level.
    public mutating func lost() -> LevelEvent? {
        defer { isLevel = false; since = nil }
        return isLevel ? .left : nil
    }
}

/// A tick each time either angle moves a whole step, stronger the closer the phone is to level. A step of
/// hysteresis and a minimum gap between ticks keep tremor and mount wobble from buzzing.
public struct DegreeTicker: Sendable {
    private let config: LevelConfig
    private var anchors: (tilt: Double, aim: Double)?
    private var lastTick: TimeInterval?

    public init(config: LevelConfig) { self.config = config }

    /// A tick's intensity (0...1), or nil for no tick.
    public mutating func update(tilt: Double, aim: Double, at time: TimeInterval) -> Double? {
        guard let anchors else {
            anchors = (rounded(tilt), rounded(aim))
            return nil
        }
        let step = config.tickStepDeg
        guard abs(tilt - anchors.tilt) >= step || abs(aim - anchors.aim) >= step else { return nil }
        if let lastTick, time - lastTick < config.tickMinIntervalS { return nil }
        self.anchors = (rounded(tilt), rounded(aim))
        lastTick = time
        let nearness = max(0, 1 - max(abs(tilt), abs(aim)) / config.tickFarDeg)
        return config.tickMinIntensity + (1 - config.tickMinIntensity) * nearness
    }

    public mutating func reset() {
        anchors = nil
        lastTick = nil
    }

    private func rounded(_ value: Double) -> Double {
        (value / config.tickStepDeg).rounded() * config.tickStepDeg
    }
}

public enum LevelHaptic: Equatable, Sendable {
    case tick(intensity: Double), success, warning
}

/// Turns motion samples into the level's pose and the haptic to play for each one.
public struct LevelGuide: Sendable {
    private let captureAngle: Double
    private let config: LevelConfig
    private var gravity: SIMD3<Double>?
    private var detector: LevelDetector
    private var ticker: DegreeTicker
    public private(set) var pose: LevelPose?

    public var isLevel: Bool { detector.isLevel }

    /// `captureAngle` is the horizon-level capture rotation the session records at (see `LevelMath.pose`).
    public init(captureAngle: Double, config: LevelConfig) {
        self.captureAngle = captureAngle
        self.config = config
        detector = LevelDetector(config: config)
        ticker = DegreeTicker(config: config)
    }

    /// One CoreMotion sample: gravity in g, rotation rate in rad/s, both in device coordinates.
    public mutating func update(gravity sample: SIMD3<Double>, rotationRate: SIMD3<Double>,
                                at time: TimeInterval) -> LevelHaptic? {
        let smoothed = gravity.map { $0 + config.smoothing * (sample - $0) } ?? sample
        gravity = smoothed
        let pose = LevelMath.pose(gravity: smoothed, captureAngle: captureAngle, flatGravity: config.flatGravity)
        self.pose = pose
        guard case let .aligned(tilt, aim) = pose else {
            ticker.reset()
            return detector.lost() == .left ? .warning : nil
        }
        let rate = (rotationRate * rotationRate).sum().squareRoot()
        let event = detector.update(tilt: tilt, aim: aim, rotationRate: rate, at: time)
        let tick = ticker.update(tilt: tilt, aim: aim, at: time)
        switch event {
        case .reached: return .success
        case .left: return .warning
        case nil: return tick.map { .tick(intensity: $0) }
        }
    }
}
