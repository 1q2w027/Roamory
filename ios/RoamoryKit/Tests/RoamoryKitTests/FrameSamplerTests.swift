import CoreVideo
import ImageIO
import XCTest
@testable import RoamoryKit

/// A BGRA pixel buffer filled with one gray level.
func solidBGRA(width: Int, height: Int, gray: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &buffer)
    let pb = buffer!
    CVPixelBufferLockBaseAddress(pb, [])
    let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
    let rowBytes = CVPixelBufferGetBytesPerRow(pb)
    for y in 0..<height {
        for x in 0..<width {
            let p = base + y * rowBytes + x * 4
            p[0] = gray; p[1] = gray; p[2] = gray; p[3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, [])
    return pb
}

final class FrameSamplerTests: XCTestCase {
    func testLumaSizeAndValue() {
        let f = FrameSampler.luma(solidBGRA(width: 1920, height: 1080, gray: 200), width: 160, height: 90)
        XCTAssertEqual(f.width, 160)
        XCTAssertEqual(f.height, 90)
        XCTAssertEqual(f.pixels.count, 14_400)
        XCTAssertEqual(Double(f.pixels[7_000]), 200, accuracy: 3)
        XCTAssertEqual(Double(f.pixels[0]), 200, accuracy: 3)  // edges are not darkened by the scaler
    }

    func testJpegLongEdge() throws {
        let data = try XCTUnwrap(FrameSampler.jpeg(solidBGRA(width: 1080, height: 1920, gray: 90), longEdge: 512, quality: 0.7))
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 512)
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 288)
    }

    func testOrientationFromTrackTransform() {
        XCTAssertEqual(FrameSampler.orientation(for: .identity), .up)
        XCTAssertEqual(FrameSampler.orientation(for: CGAffineTransform(rotationAngle: .pi / 2)), .right)  // iPhone portrait
        XCTAssertEqual(FrameSampler.orientation(for: CGAffineTransform(rotationAngle: -.pi / 2)), .left)
        XCTAssertEqual(FrameSampler.orientation(for: CGAffineTransform(rotationAngle: .pi)), .down)
    }

    func testJpegAppliesOrientation() throws {
        // A portrait recording stored as a landscape buffer with a 90 degree transform.
        let data = try XCTUnwrap(FrameSampler.jpeg(solidBGRA(width: 1920, height: 1080, gray: 90), longEdge: 512,
                                                   quality: 0.7, orientation: .right))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 288)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 512)
    }

    func testLumaAppliesOrientation() {
        // Left half black, right half white; rotated 90 degrees clockwise, the top half is black.
        let pb = solidBGRA(width: 320, height: 180, gray: 255)
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<180 { for x in 0..<160 { let p = base + y * rowBytes + x * 4; p[0] = 0; p[1] = 0; p[2] = 0 } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let f = FrameSampler.luma(pb, width: 90, height: 160, orientation: .right)
        XCTAssertLessThan(Double(f.pixels[10 * 90 + 45]), 30)     // near the top
        XCTAssertGreaterThan(Double(f.pixels[150 * 90 + 45]), 225) // near the bottom
    }
}
