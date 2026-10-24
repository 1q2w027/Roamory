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
}
