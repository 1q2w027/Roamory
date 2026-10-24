import XCTest
@testable import RoamoryKit

/// The bundled copy of contracts/style_presets.json decodes, round-trips, and matches the contract.
final class ContractsTests: XCTestCase {
    private func jsonObject(_ data: Data) throws -> NSObject {
        try JSONSerialization.jsonObject(with: data) as! NSObject
    }

    func testStylePresetsRoundTrip() throws {
        let original = try Fixtures.data("style_presets.json")
        let encoded = try JSONEncoder().encode(JSONDecoder().decode(StylePresets.self, from: original))
        XCTAssertEqual(try jsonObject(encoded), try jsonObject(original))
    }

    func testBundledStylePresetsMatchTheContract() throws {
        let bundled = try StylePresets.bundled()
        XCTAssertEqual(bundled, try Fixtures.presets())
    }
}
