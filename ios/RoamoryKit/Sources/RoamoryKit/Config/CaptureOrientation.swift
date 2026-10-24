import Foundation

/// Which way the camera records for a trip (TRD 4.1): the style's aspect, so the edit never crops to another one.
/// Reels is portrait; the 16:9 styles are landscape. Fixed before capture starts and for the whole recording.
public enum CaptureOrientation: Sendable, Equatable {
    case portrait, landscape

    public init(preset: StylePreset) {
        self = preset.aspect == .portrait ? .portrait : .landscape
    }

    /// The capture rotation angle (degrees) in this orientation closest to how the phone is held, so the picture is
    /// upright whichever way it is turned. `deviceAngle` is the horizon-level capture angle; nil, or a tie, gives
    /// the default (portrait 90, landscape 0).
    public func rotationAngle(near deviceAngle: Double?) -> Double {
        let (preferred, other): (Double, Double) = self == .portrait ? (90, 270) : (0, 180)
        guard let deviceAngle else { return preferred }
        return Self.distance(deviceAngle, other) < Self.distance(deviceAngle, preferred) ? other : preferred
    }

    /// Whether a phone at this horizon-level capture angle is turned this way (within 45° of one of its angles).
    public func isHeld(at deviceAngle: Double) -> Bool {
        Self.distance(deviceAngle, rotationAngle(near: deviceAngle)) < 45
    }

    private static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360))
        return min(d, 360 - d)
    }
}
