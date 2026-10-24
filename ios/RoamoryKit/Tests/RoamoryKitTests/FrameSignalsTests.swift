import XCTest
@testable import RoamoryKit

extension LumaFrame {
    static let w = 160, h = 90

    static func solid(_ value: UInt8) -> LumaFrame {
        LumaFrame(width: w, height: h, pixels: .init(repeating: value, count: w * h))
    }

    static var checkerboard: LumaFrame {
        LumaFrame(width: w, height: h, pixels: (0..<(w * h)).map { i in (i % w + i / w) % 2 == 0 ? 0 : 255 })
    }

    static func horizontalRamp(increasing: Bool) -> LumaFrame {
        LumaFrame(width: w, height: h, pixels: (0..<(w * h)).map { i in
            let x = i % w
            return UInt8((increasing ? x : w - 1 - x) * 255 / (w - 1))
        })
    }
}

final class FrameSignalsTests: XCTestCase {
    func testFlatFrame() {
        let s = FrameSignals.compute(.solid(128), previous: nil)
        XCTAssertEqual(s.sharpness, 0)
        XCTAssertEqual(s.change, 0)
        XCTAssertEqual(s.dhash, 0)
        XCTAssertEqual(s.meanLuma, 128)
        XCTAssertEqual(s.clippedFraction, 0)
    }

    func testCheckerboardSharpness() {
        // Alternating 0/255 pixels: every interior Laplacian response is ±1020, so the variance is 1020².
        XCTAssertEqual(FrameSignals.compute(.checkerboard, previous: nil).sharpness, 1_040_400, accuracy: 1e-6)
    }

    func testChangeAgainstPrevious() {
        XCTAssertEqual(FrameSignals.compute(.solid(255), previous: .solid(0)).change, 255)
        let small = LumaFrame(width: 8, height: 8, pixels: .init(repeating: 0, count: 64))
        XCTAssertEqual(FrameSignals.compute(.solid(10), previous: small).change, 0)
    }

    func testDhashOfRamps() {
        XCTAssertEqual(FrameSignals.compute(.horizontalRamp(increasing: true), previous: nil).dhash, .max)
        XCTAssertEqual(FrameSignals.compute(.horizontalRamp(increasing: false), previous: nil).dhash, 0)
        XCTAssertEqual(hammingDistance(0, .max), 64)
    }

    func testClippedFraction() {
        XCTAssertEqual(FrameSignals.compute(.solid(0), previous: nil).clippedFraction, 1)
        XCTAssertEqual(FrameSignals.compute(.solid(250), previous: nil).clippedFraction, 1)
        XCTAssertEqual(FrameSignals.compute(.solid(16), previous: nil).clippedFraction, 0)
    }
}
