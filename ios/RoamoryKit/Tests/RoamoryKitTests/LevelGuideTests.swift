import XCTest
@testable import RoamoryKit

final class LevelGuideTests: XCTestCase {
    private var config: LevelConfig!
    override func setUpWithError() throws { config = try LevelConfig.bundled(); config.smoothing = 1 }

    func testLevelNeedsHalfAStillSecond() {
        var d = LevelDetector(config: config)
        XCTAssertNil(d.update(tilt: 2, aim: 4, rotationRate: 0.2, at: 0))
        XCTAssertNil(d.update(tilt: 2, aim: 4, rotationRate: 0.2, at: 0.49))
        XCTAssertEqual(d.update(tilt: 2, aim: 4, rotationRate: 0.2, at: 0.5), .reached)
        XCTAssertNil(d.update(tilt: 2, aim: 4, rotationRate: 0.2, at: 1.0))
        XCTAssertTrue(d.isLevel)
    }

    func testAimIsLooserThanTilt() {
        var d = LevelDetector(config: config)
        _ = d.update(tilt: 3, aim: 0, rotationRate: 0, at: 0)
        XCTAssertNil(d.update(tilt: 3, aim: 0, rotationRate: 0, at: 1))
        _ = d.update(tilt: 0, aim: 4.5, rotationRate: 0, at: 2)
        XCTAssertEqual(d.update(tilt: 0, aim: 4.5, rotationRate: 0, at: 2.5), .reached)
    }

    func testMovingThroughLevelDoesNotCount() {
        var d = LevelDetector(config: config)
        for i in 0...100 { XCTAssertNil(d.update(tilt: 0, aim: 0, rotationRate: 0.5, at: Double(i) * 0.02)) }
        XCTAssertFalse(d.isLevel)
    }

    func testLeavingToleranceRestartsTheCount() {
        var d = LevelDetector(config: config)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0)
        _ = d.update(tilt: 3, aim: 0, rotationRate: 0, at: 0.4)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0.5)
        XCTAssertNil(d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0.95))
        XCTAssertEqual(d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1.0), .reached)
    }

    func testLeftNeedsMoreThanTheLeaveThreshold() {
        var d = LevelDetector(config: config)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1)
        XCTAssertNil(d.update(tilt: 3.5, aim: 0, rotationRate: 0, at: 1.1))
        XCTAssertNil(d.update(tilt: 0, aim: -7, rotationRate: 0, at: 1.2))
        XCTAssertEqual(d.update(tilt: 0, aim: -8.5, rotationRate: 0, at: 1.3), .left)
        XCTAssertNil(d.update(tilt: 0, aim: -8.5, rotationRate: 0, at: 1.4))
    }

    func testLostWarnsOnlyWhenLevel() {
        var d = LevelDetector(config: config)
        XCTAssertNil(d.lost())
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1)
        XCTAssertEqual(d.lost(), .left)
        XCTAssertNil(d.lost())
    }

    func testTicksOncePerWholeDegree() {
        var t = DegreeTicker(config: config)
        XCTAssertNil(t.update(tilt: 5, aim: 0, at: 0))
        XCTAssertNil(t.update(tilt: 4.5, aim: 0, at: 0.1))
        XCTAssertNotNil(t.update(tilt: 4, aim: 0, at: 0.2))
        XCTAssertNil(t.update(tilt: 3.9, aim: 0, at: 0.3))
        XCTAssertNotNil(t.update(tilt: 3, aim: 0, at: 0.4))
    }

    func testEitherAxisTicks() {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 2, aim: 2, at: 0)
        XCTAssertNotNil(t.update(tilt: 2, aim: 3, at: 0.1))
    }

    func testNoiseAroundADegreeDoesNotTick() {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 3, aim: 0, at: 0)
        for (i, v) in [2.6, 3.4, 2.6, 3.4, 2.6].enumerated() { XCTAssertNil(t.update(tilt: v, aim: 0, at: 0.1 * Double(i + 1))) }
    }

    func testTicksAreRateLimited() {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 5, aim: 0, at: 0)
        XCTAssertNotNil(t.update(tilt: 4, aim: 0, at: 0.10))
        XCTAssertNil(t.update(tilt: 3, aim: 0, at: 0.13))
        XCTAssertNotNil(t.update(tilt: 3, aim: 0, at: 0.20))
    }

    func testTicksGetStrongerNearLevel() throws {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 12, aim: 0, at: 0)
        XCTAssertEqual(try XCTUnwrap(t.update(tilt: 11, aim: 0, at: 0.1)), 0.3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(t.update(tilt: 9, aim: 0, at: 0.2)), 0.37, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(t.update(tilt: 1, aim: 0, at: 0.3)), 0.93, accuracy: 0.001)
    }

    func testSuccessOnlyOnce() {
        var g = LevelGuide(captureAngle: 90, config: config)
        var events: [LevelHaptic] = []
        for i in 0...150 { if let e = g.update(gravity: SIMD3(0, -1, 0), rotationRate: .zero, at: Double(i) * 0.02) { events.append(e) } }
        XCTAssertEqual(events, [.success])
        XCTAssertTrue(g.isLevel)
    }

    func testTurningOverAfterLevelWarnsOnce() {
        var g = LevelGuide(captureAngle: 90, config: config)
        for i in 0...60 { _ = g.update(gravity: SIMD3(0, -1, 0), rotationRate: .zero, at: Double(i) * 0.02) }
        XCTAssertEqual(g.update(gravity: SIMD3(0, 1, 0), rotationRate: .zero, at: 1.3), .warning)
        XCTAssertNil(g.update(gravity: SIMD3(0, 1, 0), rotationRate: .zero, at: 1.32))
        XCTAssertEqual(g.pose, .turnOver)
    }

    func testNoTicksWhilePrompting() {
        var g = LevelGuide(captureAngle: 0, config: config)
        for i in 0...20 {
            let a = Double(i) * .pi / 180
            XCTAssertNil(g.update(gravity: SIMD3(sin(a), -cos(a), 0), rotationRate: .zero, at: Double(i) * 0.1))
        }
        XCTAssertEqual(g.pose, .turnSideways)
    }

    func testSmoothingDampsASpike() throws {
        var c = config!; c.smoothing = 0.2
        var g = LevelGuide(captureAngle: 90, config: c)
        for i in 0..<10 { _ = g.update(gravity: SIMD3(0, -1, 0), rotationRate: .zero, at: Double(i) * 0.02) }
        let a = 30 * Double.pi / 180
        _ = g.update(gravity: SIMD3(sin(a), -cos(a), 0), rotationRate: .zero, at: 0.2)
        guard case .aligned(let tilt, _) = try XCTUnwrap(g.pose) else { return XCTFail("expected aligned") }
        XCTAssertLessThan(tilt, 10)
    }
}
