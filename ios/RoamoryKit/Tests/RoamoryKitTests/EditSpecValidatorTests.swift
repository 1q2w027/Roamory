import XCTest
@testable import RoamoryKit

final class EditSpecValidatorTests: XCTestCase {
    private var presets: StylePresets!

    override func setUpWithError() throws {
        presets = try Fixtures.presets()
    }

    /// Validates `spec` after `mutate` against the matching example request.
    private func errors(_ style: Style, _ mutate: (inout EditSpec, inout PlanRequest) -> Void = { _, _ in }) throws -> [EditSpecError] {
        var spec = try Fixtures.editSpec(style)
        var request = try Fixtures.planRequest(style)
        mutate(&spec, &request)
        return EditSpecValidator.validate(spec, request: request, preset: presets[style])
    }

    // MARK: Effective target

    func testEffectiveTarget() throws {
        let reels = presets[.reels]
        XCTAssertEqual(EffectiveTarget.seconds(buttonCount: 0, preset: reels), 30)
        // 12 x 1.5 + 2 = 20 stays under the 30 s target.
        XCTAssertEqual(EffectiveTarget.seconds(buttonCount: 12, preset: reels), 30)
        // 24 x 1.5 + 2 = 38: button moments push the video past the target.
        XCTAssertEqual(EffectiveTarget.seconds(buttonCount: 24, preset: reels), 38)
        XCTAssertEqual(EffectiveTarget.seconds(buttonCount: 12, preset: presets[.documentary]), 62)
        for style in Style.allCases {
            let request = try Fixtures.planRequest(style)
            let buttons = request.clips.count(where: { $0.source == .button })
            XCTAssertEqual(EffectiveTarget.seconds(buttonCount: buttons, preset: presets[style]), request.effectiveTargetS)
        }
    }

    // MARK: Rules

    func testContractExamplesAreValid() throws {
        for style in Style.allCases {
            XCTAssertEqual(try errors(style), [], "\(style)")
        }
    }

    func testUnknownAndDuplicateMoments() throws {
        XCTAssertEqual(try errors(.reels) { spec, _ in spec.clips[0].momentId = "m_99" }.first,
                       .unknownMoment(index: 0, momentId: "m_99"))
        let dup = try errors(.reels) { spec, _ in spec.clips[1] = spec.clips[0] }
        XCTAssertTrue(dup.contains(.duplicateMoment(index: 1, momentId: "m_01")))
    }

    func testTrimBounds() throws {
        let past = try errors(.reels) { spec, _ in spec.clips[0].inS = 30; spec.clips[0].outS = 32.5 }
        XCTAssertTrue(past.contains(.trimOutOfBounds(index: 0, momentId: "m_01", inS: 30, outS: 32.5, durationS: 32)))
        let negative = try errors(.reels) { spec, _ in spec.clips[0].inS = -0.5; spec.clips[0].outS = 2 }
        XCTAssertTrue(negative.contains { if case .trimOutOfBounds = $0 { true } else { false } })
        let reversed = try errors(.reels) { spec, _ in spec.clips[0].inS = 17.3; spec.clips[0].outS = 14.8 }
        XCTAssertTrue(reversed.contains { if case .trimOutOfBounds = $0 { true } else { false } })
    }

    func testClipLength() throws {
        let long = try errors(.reels) { spec, _ in spec.clips[0].outS = spec.clips[0].inS + 3.5 }
        XCTAssertTrue(long.contains { if case .clipLengthOutOfRange(0, "m_01", _, 1.5, 3) = $0 { true } else { false } })
        let short = try errors(.reels) { spec, _ in spec.clips[0].outS = spec.clips[0].inS + 1 }
        XCTAssertTrue(short.contains { if case .clipLengthOutOfRange(0, _, _, _, _) = $0 { true } else { false } })
    }

    func testButtonMomentsRequired() throws {
        let missing = try errors(.reels) { spec, _ in spec.clips.removeAll { $0.momentId == "m_06" } }
        XCTAssertTrue(missing.contains(.missingButtonMoment(momentId: "m_06")))
    }

    func testTransitionSMustMatchCut() throws {
        XCTAssertTrue(try errors(.reels) { spec, _ in spec.clips[2].transitionS = 0.5 }
            .contains(.transitionMismatch(index: 2, momentId: "m_03")))
        XCTAssertTrue(try errors(.cinematic) { spec, _ in spec.clips[1].transitionS = 0 }
            .contains { if case .transitionMismatch(1, _) = $0 { true } else { false } })
    }

    func testSpeedRampRules() throws {
        let ramp = EditSpec.SpeedRamp(from: 4, to: 1, overS: 1)
        // Documentary doesn't allow ramps.
        XCTAssertTrue(try errors(.documentary) { spec, _ in spec.clips[0].speedRamp = ramp }
            .contains { if case .speedRampNotAllowed(0, _) = $0 { true } else { false } })
        // m_01 has no low-fps lead-in.
        XCTAssertTrue(try errors(.reels) { spec, _ in spec.clips[0].speedRamp = ramp }
            .contains(.speedRampOutsideLeadIn(index: 0, momentId: "m_01", leadInS: 0)))
        // m_03 has a 15 s lead-in but the ramp can't run past the trim.
        let tooLong = try errors(.reels) { spec, _ in
            spec.clips[2].inS = 11; spec.clips[2].outS = 13.5
            spec.clips[2].speedRamp = EditSpec.SpeedRamp(from: 4, to: 1, overS: 3)
        }
        XCTAssertTrue(tooLong.contains(.speedRampTooLong(index: 2, momentId: "m_03")))
    }

    func testCaptions() throws {
        XCTAssertTrue(try errors(.reels) { spec, _ in spec.clips[0].caption = "Kyoto" }
            .contains(.captionNotAllowed(index: 0, momentId: "m_01")))
        XCTAssertTrue(try errors(.documentary) { spec, _ in spec.clips[0].caption = "A geisha dances" }
            .contains(.captionNotInAllowedList(index: 0, momentId: "m_01", caption: "A geisha dances")))
        for allowed in ["Kyoto", "Japan", "Kyoto, Japan", "honeymoon", "Bowl of ramen on a wooden counter"] {
            XCTAssertEqual(try errors(.documentary) { spec, _ in spec.clips[0].caption = allowed }, [], allowed)
        }
        // No city: only the country stands in for the place.
        XCTAssertFalse(EditSpecValidator.allowedCaptions(try {
            var request = try Fixtures.planRequest(.documentary)
            request.destination.city = nil
            return request
        }()).contains("Kyoto"))
    }

    func testTotalDuration() throws {
        // Same totals as backend/app/plan/validate.py on the examples.
        XCTAssertEqual(EditTimeline.totalDurationS(try Fixtures.editSpec(.reels)), 29.0208, accuracy: 1e-4)
        XCTAssertEqual(EditTimeline.totalDurationS(try Fixtures.editSpec(.cinematic)), 50.2417, accuracy: 1e-4)
        XCTAssertEqual(EditTimeline.totalDurationS(try Fixtures.editSpec(.documentary)), 60, accuracy: 1e-6)
        let tooLong = try errors(.reels) { _, request in request.effectiveTargetS = 20 }
        XCTAssertTrue(tooLong.contains { if case .durationOutOfRange = $0 { true } else { false } })
        let tooShort = try errors(.reels) { _, request in request.effectiveTargetS = 40 }
        XCTAssertTrue(EditSpecValidator.onlyTooShort(tooShort))
        XCTAssertFalse(EditSpecValidator.onlyTooShort(tooLong))
    }

    func testTransitionsOverlapButNotOnTheFirstClip() throws {
        let cinematic = try Fixtures.editSpec(.cinematic)
        let slots = EditTimeline.slots(cinematic)
        XCTAssertEqual(slots[0].startS, 0)
        XCTAssertEqual(slots[1].startS, slots[0].endS - cinematic.clips[1].transitionS, accuracy: 1e-9)
        let cuts = cinematic.withHardCuts()
        XCTAssertGreaterThan(EditTimeline.totalDurationS(cuts), EditTimeline.totalDurationS(cinematic))
    }

    func testSpeedRampOutputLength() {
        // 4 steps of 0.25 s at 4, 3, 2, 1x: 0.0625 + 0.0833 + 0.125 + 0.25 = 0.5208, plus 2 real-time seconds.
        let clip = EditSpec.Clip(momentId: "m", inS: 13.5, outS: 16.5, transitionIn: .cut, transitionS: 0,
                                 speedRamp: .init(from: 4, to: 1, overS: 1), caption: nil)
        XCTAssertEqual(EditTimeline.outputLengthS(clip), 2 + 0.0625 + 0.25 / 3 + 0.125 + 0.25, accuracy: 1e-9)
    }
}
