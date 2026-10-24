import Foundation

/// How the phone sits relative to the frame the trip records, for the mount level.
public enum LevelPose: Equatable, Sendable {
    /// Turned the recorded way round. `tilt` > 0: the frame's right side is low; `aim` > 0: the camera points up.
    /// Both in degrees, 0 when level.
    case aligned(tilt: Double, aim: Double)
    /// A 16:9 trip, but the phone is upright.
    case turnSideways
    /// A Reels trip, but the phone is on its side.
    case holdUpright
    /// The right orientation, but upside down from the side the session records.
    case turnOver
}

public enum LevelMath {
    /// The pose for a gravity sample. `gravity` is in CoreMotion device coordinates (x to the right of the screen,
    /// y to its top, z out of it, in g). `captureAngle` is the horizon-level capture rotation the session records at,
    /// in degrees: 90 portrait, 0 with the top of the phone to the left, 180 to the right. Below `flatGravity` in the
    /// screen's plane the phone lies flat, tilt is undefined and reads 0.
    public static func pose(gravity: SIMD3<Double>, captureAngle: Double, flatGravity: Double) -> LevelPose {
        let length = (gravity * gravity).sum().squareRoot()
        guard length > 0 else { return .aligned(tilt: 0, aim: 0) }
        let g = gravity / length
        let theta = captureAngle * .pi / 180
        // The recorded frame's up and right, in device coordinates.
        let up = SIMD3(-cos(theta), sin(theta), 0)
        let right = SIMD3(sin(theta), -cos(theta), 0)
        let down = -(g * up).sum()
        let side = (g * right).sum()
        let aim = asin(min(max(g.z, -1), 1)) * 180 / .pi
        if hypot(down, side) < flatGravity { return .aligned(tilt: 0, aim: aim) }
        let phi = atan2(side, down) * 180 / .pi
        if abs(phi) <= 45 { return .aligned(tilt: phi, aim: aim) }
        if abs(phi) >= 135 { return .turnOver }
        return abs(cos(theta)) > abs(sin(theta)) ? .turnSideways : .holdUpright
    }
}
