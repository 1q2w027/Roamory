import XCTest
@testable import RoamoryKit

/// Codable mirrors decode every contracts example and encode back to the same JSON.
final class ContractsTests: XCTestCase {
    private func assertRoundTrip<T: Codable>(_ type: T.Type, _ path: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let original = try Fixtures.data(path)
        let decoded = try JSONDecoder().decode(T.self, from: original)
        let encoded = try JSONEncoder().encode(decoded)
        XCTAssertEqual(try jsonObject(encoded), try jsonObject(original), "\(path) changed in a round trip", file: file, line: line)
    }

    func testPlanRequestExamplesRoundTrip() throws {
        for style in Style.allCases {
            try assertRoundTrip(PlanRequest.self, "examples/plan_request_\(style.rawValue).json")
        }
    }

    func testEditSpecExamplesRoundTrip() throws {
        for style in Style.allCases {
            try assertRoundTrip(EditSpec.self, "examples/edit_spec_\(style.rawValue).json")
        }
    }

    func testPresetsAndSidecarRoundTrip() throws {
        try assertRoundTrip(StylePresets.self, "style_presets.json")
        try assertRoundTrip(ClipSidecar.self, "examples/clip_sidecar_m_03.json")
    }

    func testNullableFieldsEncodeAsExplicitNull() throws {
        let clip = EditSpec.Clip(momentId: "m_01", inS: 0, outS: 2, transitionIn: .cut, transitionS: 0, speedRamp: nil, caption: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as! [String: Any]
        XCTAssertTrue(object["speed_ramp"] is NSNull)
        XCTAssertTrue(object["caption"] is NSNull)

        let destination = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Destination(country: "Japan", city: nil))) as! [String: Any]
        XCTAssertTrue(destination["city"] is NSNull)
    }

    func testBundledPresetsMatchContracts() throws {
        let bundled = try XCTUnwrap(BundledResources.url("style_presets", ext: "json"))
        XCTAssertEqual(try Data(contentsOf: bundled), try Fixtures.data("style_presets.json"),
                       "Run ios/RoamoryKit/scripts/sync-contracts.sh")
        XCTAssertEqual(try StylePresets.bundled().presets.count, 4)
    }

    func testBundledMediaExists() {
        for style in Style.allCases {
            let track = try! StylePresets.bundled()[style].musicTrack
            XCTAssertNotNil(BundledResources.musicURL(track: track), "no music for \(track)")
        }
        XCTAssertNotNil(BundledResources.blackClipURL(portrait: false))
        XCTAssertNotNil(BundledResources.blackClipURL(portrait: true))
        XCTAssertFalse(BundledResources.sampleClipURLs.isEmpty)
    }

    func testSidecarToClipInfo() throws {
        let sidecar = try Fixtures.decode(ClipSidecar.self, "examples/clip_sidecar_m_03.json")
        let folder = URL(fileURLWithPath: "/trips/t_123")
        let info = ClipInfo(sidecar: sidecar, moment: MomentFields(score: 0.71), tripFolder: folder)
        XCTAssertEqual(info.clipURL.path, "/trips/t_123/clips/m_03.mp4")
        XCTAssertEqual(info.triggerS, 15, accuracy: 1e-9)
        XCTAssertEqual(info.lowFpsLeadInS(fullFpsMin: Fixtures.config.fullFpsMin), 15)
        // Sharpest sample (t = 15 s) gives the best-frame hash.
        XCTAssertEqual(info.bestFrameDhash, 0x0e1e3f3f1f1e0e06)
        XCTAssertTrue(info.isButton)
    }
}
