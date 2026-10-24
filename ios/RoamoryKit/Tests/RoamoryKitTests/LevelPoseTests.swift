import XCTest
@testable import RoamoryKit

private func rad(_ d: Double) -> Double { d * .pi / 180 }

private func assertAligned(_ pose: LevelPose, tilt: Double, aim: Double,
                           file: StaticString = #filePath, line: UInt = #line) {
    guard case let .aligned(t, a) = pose else { return XCTFail("expected aligned, got \(pose)", file: file, line: line) }
    XCTAssertEqual(t, tilt, accuracy: 0.01, file: file, line: line)
    XCTAssertEqual(a, aim, accuracy: 0.01, file: file, line: line)
}

final class LevelPoseTests: XCTestCase {
    private func pose(_ x: Double, _ y: Double, _ z: Double, _ angle: Double) -> LevelPose {
        LevelMath.pose(gravity: SIMD3(x, y, z), captureAngle: angle, flatGravity: 0.35)
    }

    func testUprightPortraitIsLevel() { assertAligned(pose(0, -1, 0, 90), tilt: 0, aim: 0) }

    func testRightSideLowGivesPositiveTilt() {
        assertAligned(pose(sin(rad(10)), -cos(rad(10)), 0, 90), tilt: 10, aim: 0)
    }

    func testCameraAimedUpGivesPositiveAim() {
        assertAligned(pose(0, -cos(rad(5)), sin(rad(5)), 90), tilt: 0, aim: 5)
    }

    func testLandscapeRightSideLowOnEachSide() {
        // Top of the phone to the left: its right edge points up, so gravity is along -x.
        assertAligned(pose(-1, 0, 0, 0), tilt: 0, aim: 0)
        assertAligned(pose(1, 0, 0, 180), tilt: 0, aim: 0)                        // top to the right
        assertAligned(pose(-cos(rad(10)), -sin(rad(10)), 0, 0), tilt: 10, aim: 0)
        assertAligned(pose(cos(rad(10)), sin(rad(10)), 0, 180), tilt: 10, aim: 0)
    }

    func testWrongOrientationPrompts() {
        XCTAssertEqual(pose(0, -1, 0, 0), .turnSideways)     // 16:9 trip, phone upright
        XCTAssertEqual(pose(0, -1, 0, 180), .turnSideways)
        XCTAssertEqual(pose(1, 0, 0, 90), .holdUpright)      // Reels trip, phone sideways
    }

    func testOtherSideUpPromptsTurnOver() {
        XCTAssertEqual(pose(1, 0, 0, 0), .turnOver)
        XCTAssertEqual(pose(-1, 0, 0, 180), .turnOver)
        XCTAssertEqual(pose(0, 1, 0, 90), .turnOver)
    }

    func testFlatPhoneStaysAligned() {
        assertAligned(pose(0, 0, -1, 90), tilt: 0, aim: -90)
        guard case .aligned(let tilt, _) = pose(0.1, 0.1, -0.99, 0) else { return XCTFail("expected aligned") }
        XCTAssertEqual(tilt, 0)
    }

    func testBundledConfigMatchesSpec() throws {
        let config = try LevelConfig.bundled()
        XCTAssertEqual(config.toleranceDeg, 1)
        XCTAssertEqual(config.leaveDeg, 2)
        XCTAssertEqual(config.settleS, 1)
        XCTAssertEqual(config.stillRadS, 0.15)
    }
}
