import CoreImage
import CoreVideo
import Foundation

/// Turns a camera or decoded-video pixel buffer (BGRA or 420 bi-planar) into what Stage 1 needs:
/// a small grayscale copy for the signals and a JPEG for the cloud.
/// `orientation` rotates the buffer upright first: a decoded iPhone video needs its track's `preferredTransform`
/// (see `orientation(for:)`); live capture can instead set `videoRotationAngle` on the output connection.
public enum FrameSampler {
    /// No color management, so a gray level stays the same number through scaling.
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The orientation that makes a video track upright, from its `preferredTransform` (multiples of 90 degrees).
    public static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let quarterTurns = Int((atan2(transform.b, transform.a) / (.pi / 2)).rounded())
        switch (quarterTurns % 4 + 4) % 4 {
        case 1: return .right
        case 2: return .down
        case 3: return .left
        default: return .up
        }
    }

    private static func upright(_ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation) -> CIImage {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// Scales to exactly `width × height` and converts to Rec. 601 luma.
    public static func luma(_ buffer: CVPixelBuffer, width: Int, height: Int,
                            orientation: CGImagePropertyOrientation = .up) -> LumaFrame {
        let image = upright(buffer, orientation)
        let sx = CGFloat(width) / image.extent.width, sy = CGFloat(height) / image.extent.height
        let rec601 = CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0)
        let gray = image
            .clampedToExtent()  // keeps the scaler from blending transparent pixels into the edges
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": rec601, "inputGVector": rec601, "inputBVector": rec601,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { raw in
            context.render(gray, toBitmap: raw.baseAddress!, rowBytes: width,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .L8, colorSpace: nil)
        }
        return LumaFrame(width: width, height: height, pixels: pixels)
    }

    /// Scales so the long edge is `longEdge` px and encodes a JPEG at `quality` (0…1).
    public static func jpeg(_ buffer: CVPixelBuffer, longEdge: Int, quality: Double,
                            orientation: CGImagePropertyOrientation = .up) -> Data? {
        let image = upright(buffer, orientation)
        let scale = CGFloat(longEdge) / max(image.extent.width, image.extent.height)
        let size = CGSize(width: (image.extent.width * scale).rounded(), height: (image.extent.height * scale).rounded())
        let scaled = image
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .cropped(to: CGRect(origin: .zero, size: size))
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality]
        return context.jpegRepresentation(of: scaled, colorSpace: sRGB, options: options)
    }
}
