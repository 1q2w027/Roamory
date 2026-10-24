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

    func testEvaluateExamplesRoundTrip() throws {
        try assertRoundTrip(EvaluateContext.self, "examples/evaluate_context_select.json")
        try assertRoundTrip(EvaluateContext.self, "examples/evaluate_context_describe.json")
        try assertRoundTrip(Evaluation.self, "examples/evaluation_save.json")
        try assertRoundTrip(Evaluation.self, "examples/evaluation_skip.json")
    }

    func testRenderExamplesRoundTrip() throws {
        for style in Style.allCases {
            try assertRoundTrip(RenderRequest.self, "examples/render_request_\(style.rawValue).json")
        }
        try assertRoundTrip(RenderJob.self, "examples/render_job_rendering.json")
        try assertRoundTrip(RenderJob.self, "examples/render_job_failed.json")
    }

    func testAgentExamplesRoundTrip() throws {
        for style in Style.allCases {
            try assertRoundTrip(AgentRequest.self, "examples/agent_request_\(style.rawValue).json")
        }
        try assertRoundTrip(AgentResult.self, "examples/agent_result_reels.json")
    }

    /// The agent request carries the plan request's clip fields, so both examples agree for the same trip.
    func testAgentRequestMatchesThePlanRequest() throws {
        for style in Style.allCases {
            let agent = try Fixtures.decode(AgentRequest.self, "examples/agent_request_\(style.rawValue).json")
            let plan = try Fixtures.planRequest(style)
            XCTAssertEqual(agent.effectiveTargetS, plan.effectiveTargetS, "\(style)")
            XCTAssertEqual(agent.context, RenderRequest.Context(destination: plan.destination, tripType: plan.tripType, startDate: plan.startDate))
            XCTAssertEqual(agent.clips.map(\.momentId), plan.clips.map(\.momentId))
            for (a, p) in zip(agent.clips, plan.clips) {
                XCTAssertEqual([a.proposedInS, a.proposedOutS, a.lowFpsLeadInS], [p.proposedInS, p.proposedOutS, p.lowFpsLeadInS], a.momentId)
                XCTAssertEqual(a.source, p.source)
            }
        }
    }

    /// Golden timelines (contracts README): both engines place every clip at the same time, within 1 ms.
    func testEditTimelineMatchesTheGoldenTimelines() throws {
        struct Golden: Decodable {
            struct Slot: Decodable {
                var moment_id: String
                var start_s: Double
                var end_s: Double
            }
            var slots: [Slot]
            var end_card_start_s: Double
            var total_s: Double
        }
        for style in Style.allCases {
            let golden = try Fixtures.decode(Golden.self, "examples/timeline_\(style.rawValue).json")
            let spec = try Fixtures.editSpec(style)
            let slots = EditTimeline.slots(spec)
            XCTAssertEqual(slots.map(\.momentId), golden.slots.map(\.moment_id), "\(style)")
            for (slot, want) in zip(slots, golden.slots) {
                XCTAssertEqual(slot.startS, want.start_s, accuracy: 0.001, "\(style) \(slot.momentId)")
                XCTAssertEqual(slot.endS, want.end_s, accuracy: 0.001, "\(style) \(slot.momentId)")
            }
            XCTAssertEqual(slots.last?.endS ?? 0, golden.end_card_start_s, accuracy: 0.001, "\(style)")
            XCTAssertEqual(EditTimeline.totalDurationS(spec), golden.total_s, accuracy: 0.001, "\(style)")

            // The rebased spec in the render request keeps the same timeline.
            let rebased = try Fixtures.decode(RenderRequest.self, "examples/render_request_\(style.rawValue).json").editSpec
            XCTAssertEqual(EditTimeline.totalDurationS(rebased), golden.total_s, accuracy: 0.001, "\(style) rebased")
        }
    }

    func testEvaluateDestinationEncodesExplicitNull() throws {
        let d = EvaluateContext.Destination(continent: nil, country: "Japan", city: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        XCTAssertTrue(object["continent"] is NSNull)
        XCTAssertTrue(object["city"] is NSNull)
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
