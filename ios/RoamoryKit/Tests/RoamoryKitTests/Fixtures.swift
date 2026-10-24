import Foundation
@testable import RoamoryKit

/// Reads `contracts/` from the repo checkout, so tests use the shared examples directly.
enum Fixtures {
    static let contracts = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent()  // RoamoryKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // RoamoryKit
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo root
        .appending(path: "contracts")

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: contracts.appending(path: path))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(path))
    }

    static func planRequest(_ style: Style) throws -> PlanRequest {
        try decode(PlanRequest.self, "examples/plan_request_\(style.rawValue).json")
    }

    static func editSpec(_ style: Style) throws -> EditSpec {
        try decode(EditSpec.self, "examples/edit_spec_\(style.rawValue).json")
    }

    static func presets() throws -> StylePresets {
        try decode(StylePresets.self, "style_presets.json")
    }

    static let config = try! EditConfig.bundled()

    /// A plan-request clip with sensible defaults for rule tests.
    static func clip(
        _ id: String, at minute: Int, source: MomentSource = .ai, score: Double? = 0.5, durationS: Double = 32,
        description: String? = nil, leadInS: Double = 0
    ) -> PlanRequest.Clip {
        let fromMs = minute * 60_000
        return PlanRequest.Clip(
            momentId: id, tFromMs: fromMs, tToMs: fromMs + Int(durationS * 1000), durationS: durationS, source: source,
            eventType: description == nil ? nil : .scenery, description: description, score: score,
            proposedInS: durationS / 2 - 1, proposedOutS: durationS / 2 + 1, lowFpsLeadInS: leadInS, thumbnailCount: 0
        )
    }

    static func request(_ style: Style, clips: [PlanRequest.Clip], preset: StylePreset) -> PlanRequest {
        PlanRequest(
            tripId: "t_test", style: style, tripType: "honeymoon", destination: Destination(country: "Japan", city: "Kyoto"),
            startDate: "2026-10-12", targetS: preset.targetS.default,
            effectiveTargetS: EffectiveTarget.seconds(buttonCount: clips.count(where: { $0.source == .button }), preset: preset),
            clips: clips
        )
    }
}

/// JSON values compared as Foundation objects, so key order and 30 vs 30.0 don't matter.
func jsonObject(_ data: Data) throws -> NSObject {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! NSObject
}
