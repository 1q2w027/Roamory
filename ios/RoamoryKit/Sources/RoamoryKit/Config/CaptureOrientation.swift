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

    /// The interface orientation that shows a session recording at `angle` (a horizon-level capture rotation)
    /// upright: 0° has the phone's top to the left, which UIKit calls landscape right. Portrait for 90° and 270°,
    /// since the iPhone has no upside-down interface.
    public static func interfaceSide(forCaptureAngle angle: Double) -> InterfaceSide {
        let nearest = [0.0, 90, 180, 270].min { distance(angle, $0) < distance(angle, $1) } ?? 90
        switch nearest {
        case 0: return .landscapeRight
        case 180: return .landscapeLeft
        default: return .portrait
        }
    }

    private static func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360))
        return min(d, 360 - d)
    }
}

/// Which way the interface is turned, in UIKit's interface-orientation naming.
public enum InterfaceSide: Sendable, Equatable {
    case portrait, landscapeLeft, landscapeRight
}
