import XCTest
@testable import RoamoryKit

final class DetectionConfigTests: XCTestCase {
    func testBundledConfigLoadsAndWeightsSumToOne() throws {
        let c = try DetectionConfig.bundled()
        XCTAssertEqual(c.weightChangeSpike + c.weightDwell + c.weightQuality + c.weightNovelty, 1, accuracy: 1e-9)
        XCTAssertEqual(c.framesPerRequest, 3)
        XCTAssertEqual(c.cooldownS, 10)
        XCTAssertEqual(c.localFallbackMin, 0.85)
    }

    func testWindowFitsInBufferRetention() throws {
        let c = try DetectionConfig.bundled()
        XCTAssertEqual(c.preS, 15)
        XCTAssertEqual(c.postS, 15)
        // RollingRecorder keeps 45 s. A moment is cut at trigger + post + 2 s (+1 s ticker) and reaches
        // back pre + 2 s to a keyframe, so pre + post + 5 must fit or clips lose their start.
        XCTAssertLessThanOrEqual(c.preS + c.postS + 5, 45)
    }
}
