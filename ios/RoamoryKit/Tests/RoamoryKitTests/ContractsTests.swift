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

    func testPresetsAndSidecarRoundTrip() throws {
        try assertRoundTrip(StylePresets.self, "style_presets.json")
        try assertRoundTrip(ClipSidecar.self, "examples/clip_sidecar_m_03.json")
    }

    func testEvaluateExamplesRoundTrip() throws {
        try assertRoundTrip(EvaluateContext.self, "examples/evaluate_context_select.json")
        try assertRoundTrip(EvaluateContext.self, "examples/evaluate_context_describe.json")
        try assertRoundTrip(Evaluation.self, "examples/evaluation_save.json")
        try assertRoundTrip(Evaluation.self, "examples/evaluation_skip.json")
    }

    func testRenderJobExamplesRoundTrip() throws {
        try assertRoundTrip(RenderJob.self, "examples/render_job_rendering.json")
        try assertRoundTrip(RenderJob.self, "examples/render_job_failed.json")
    }

    func testAgentExamplesRoundTrip() throws {
        for style in Style.allCases {
            try assertRoundTrip(AgentRequest.self, "examples/agent_request_\(style.rawValue).json")
        }
        try assertRoundTrip(AgentResult.self, "examples/agent_result_reels.json")
    }

    func testEvaluateDestinationEncodesExplicitNull() throws {
        let d = EvaluateContext.Destination(continent: nil, country: "Japan", city: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        XCTAssertTrue(object["continent"] is NSNull)
        XCTAssertTrue(object["city"] is NSNull)
    }

    func testNullableFieldsEncodeAsExplicitNull() throws {
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
