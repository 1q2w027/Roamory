import Foundation

/// An 8-bit grayscale image, row-major. Stage 1 signals run on a small copy of each sampled frame (TRD 6).
public struct LumaFrame: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixels must hold width × height values")
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}
