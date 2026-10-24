import XCTest
@testable import RoamoryKit

final class CaptureOrientationTests: XCTestCase {
    func testReelsIsPortraitAndTheOtherStylesAreLandscape() throws {
        let presets = try StylePresets.bundled()
        XCTAssertEqual(CaptureOrientation(preset: presets[.reels]), .portrait)
        XCTAssertEqual(CaptureOrientation(preset: presets[.cinematic]), .landscape)
        XCTAssertEqual(CaptureOrientation(preset: presets[.documentary]), .landscape)
        XCTAssertEqual(CaptureOrientation(preset: presets[.vlog]), .landscape)
    }

    func testLandscapeFollowsWhicheverWayThePhoneIsTurned() {
        XCTAssertEqual(CaptureOrientation.landscape.rotationAngle(near: 170), 180)
        XCTAssertEqual(CaptureOrientation.landscape.rotationAngle(near: 10), 0)
        XCTAssertEqual(CaptureOrientation.landscape.rotationAngle(near: 350), 0)    // wraps around
        XCTAssertEqual(CaptureOrientation.landscape.rotationAngle(near: 90), 0)     // held upright: tie, default
        XCTAssertEqual(CaptureOrientation.landscape.rotationAngle(near: nil), 0)
    }

    func testPortraitFollowsWhicheverWayThePhoneIsTurned() {
        XCTAssertEqual(CaptureOrientation.portrait.rotationAngle(near: 260), 270)
        XCTAssertEqual(CaptureOrientation.portrait.rotationAngle(near: 100), 90)
        XCTAssertEqual(CaptureOrientation.portrait.rotationAngle(near: 0), 90)      // held sideways: tie, default
        XCTAssertEqual(CaptureOrientation.portrait.rotationAngle(near: nil), 90)
    }

    func testIsHeldTellsWhetherThePhoneIsTurnedTheRightWay() {
        XCTAssertTrue(CaptureOrientation.landscape.isHeld(at: 175))
        XCTAssertTrue(CaptureOrientation.landscape.isHeld(at: 20))
        XCTAssertFalse(CaptureOrientation.landscape.isHeld(at: 90))    // upright while a 16:9 style is chosen
        XCTAssertTrue(CaptureOrientation.portrait.isHeld(at: 90))
        XCTAssertFalse(CaptureOrientation.portrait.isHeld(at: 0))
    }

    func testInterfaceSideForCaptureAngle() {
        // Capture 0° is the phone's top to the left, which UIKit calls interface landscape right.
        XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 0), .landscapeRight)
        XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 180), .landscapeLeft)
        XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 175), .landscapeLeft)
        XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 90), .portrait)
        XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 270), .portrait)   // no upside-down UI on iPhone
    }
}
