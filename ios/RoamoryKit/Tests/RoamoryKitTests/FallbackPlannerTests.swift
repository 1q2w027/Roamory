import XCTest
@testable import RoamoryKit

final class FallbackPlannerTests: XCTestCase {
    private var presets: StylePresets!
    private let endCard = "Made with Roamory"

    override func setUpWithError() throws {
        presets = try Fixtures.presets()
    }

    private func plan(_ request: PlanRequest) -> EditSpec {
        FallbackPlanner.plan(request, preset: presets[request.style], endCardText: endCard)
    }

    private func validate(_ spec: EditSpec, _ request: PlanRequest) -> [EditSpecError] {
        EditSpecValidator.validate(spec, request: request, preset: presets[request.style])
    }

    func testExampleRequestsPassTheValidator() throws {
        for style in Style.allCases {
            let request = try Fixtures.planRequest(style)
            let spec = plan(request)
            XCTAssertEqual(validate(spec, request), [], "\(style)")
            XCTAssertEqual(spec.output, presets[style].output)
            XCTAssertEqual(spec.music.duckOriginalAudio, !presets[style].keepOriginalAudio)
            XCTAssertEqual(spec.title.text, "Kyoto")
            XCTAssertEqual(spec.title.subtitle, "October 2026")
            XCTAssertEqual(spec.endCard.text, endCard)
        }
    }

    func testChronologicalAndPresetDefaults() throws {
        let request = try Fixtures.planRequest(.documentary)
        let spec = plan(request)
        let starts = spec.clips.map { id in request.clips.first { $0.momentId == id.momentId }!.tFromMs }
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertTrue(spec.clips.allSatisfy { $0.transitionIn == .dissolve && $0.transitionS == 1.0 && $0.speedRamp == nil })
        // Documentary captions come from the clip descriptions only.
        let descriptions = Dictionary(uniqueKeysWithValues: request.clips.map { ($0.momentId, $0.description) })
        XCTAssertTrue(spec.clips.allSatisfy { $0.caption == descriptions[$0.momentId]! })
    }

    func testDeterministicWhateverTheInputOrder() throws {
        for style in Style.allCases {
            var request = try Fixtures.planRequest(style)
            let first = plan(request)
            XCTAssertEqual(plan(request), first)
            request.clips.reverse()
            XCTAssertEqual(plan(request), first, "\(style)")
            request.clips.swapAt(0, request.clips.count / 2)
            XCTAssertEqual(plan(request), first, "\(style)")
        }
    }

    func testHigherScoresWinTheSpace() throws {
        // Reels with 1.5-3 s clips: twenty clips can't all fit in 30 s.
        let clips = (0..<20).map { Fixtures.clip("m_\($0)", at: $0, score: Double($0) / 20) }
        let request = Fixtures.request(.reels, clips: clips, preset: presets[.reels])
        let spec = plan(request)
        XCTAssertEqual(validate(spec, request), [])
        let kept = Set(spec.clips.map(\.momentId))
        XCTAssertTrue(kept.contains("m_19"))
        XCTAssertFalse(kept.contains("m_0"))
    }

    /// Gate 10: every button press appears, even over the length target.
    func testTwelveButtonReels() {
        let buttons = (0..<12).map { Fixtures.clip("b_\($0)", at: 2 * $0, source: .button, score: nil) }
        let others = (0..<10).map { Fixtures.clip("a_\($0)", at: 2 * $0 + 1, score: 0.9) }
        let request = Fixtures.request(.reels, clips: buttons + others, preset: presets[.reels])
        XCTAssertEqual(request.effectiveTargetS, 30)
        let spec = plan(request)
        XCTAssertEqual(validate(spec, request), [])
        XCTAssertTrue(buttons.allSatisfy { b in spec.clips.contains { $0.momentId == b.momentId } })
    }

    func testButtonsBeyondTheTargetAreCutTowardTheMinimum() {
        let buttons = (0..<24).map { Fixtures.clip("b_\($0)", at: $0, source: .button) }
        let others = (0..<5).map { Fixtures.clip("a_\($0)", at: 30 + $0, score: 0.99) }
        let request = Fixtures.request(.reels, clips: buttons + others, preset: presets[.reels])
        XCTAssertEqual(request.effectiveTargetS, 38)
        let spec = plan(request)
        XCTAssertEqual(validate(spec, request), [])
        XCTAssertEqual(spec.clips.count, 24, "AI clips get no room once buttons fill the video")
        XCTAssertGreaterThan(EditTimeline.totalDurationS(spec), 30)
        XCTAssertTrue(spec.clips.allSatisfy { abs($0.sourceLengthS - 1.5) < 1e-6 })
    }

    func testTooLittleFootageIsOnlyTooShort() {
        // One 12 s clip can't make a 50 s cinematic video; clips are lengthened to clip_s.max first.
        let request = Fixtures.request(.cinematic, clips: [Fixtures.clip("m_1", at: 0, durationS: 12)], preset: presets[.cinematic])
        let spec = plan(request)
        XCTAssertEqual(spec.clips.count, 1)
        XCTAssertEqual(spec.clips[0].sourceLengthS, 8, accuracy: 1e-6)
        XCTAssertTrue(EditSpecValidator.onlyTooShort(validate(spec, request)))
    }

    func testFewClipsAreLengthenedToReachTheTarget() {
        // Vlog 50 s from seven 32 s clips: 7 x 5 s + 2 = 37 s by default, so clips grow toward 8 s.
        let clips = (0..<7).map { Fixtures.clip("m_\($0)", at: $0) }
        let request = Fixtures.request(.vlog, clips: clips, preset: presets[.vlog])
        let spec = plan(request)
        XCTAssertEqual(validate(spec, request), [])
        XCTAssertEqual(EditTimeline.totalDurationS(spec), 50, accuracy: 0.01)
    }

    func testTrimsStayInsideShortFiles() {
        var clip = Fixtures.clip("m_1", at: 0, durationS: 6.0006)
        clip.proposedInS = 5
        clip.proposedOutS = 6.0006
        let (inS, outS) = FallbackPlanner.trim(clip, length: 6)
        XCTAssertGreaterThanOrEqual(inS, 0)
        XCTAssertLessThanOrEqual(outS, 6.0006)
        XCTAssertEqual(outS - inS, 6, accuracy: 1e-9)
    }

    func testTitleWithoutACity() {
        var request = Fixtures.request(.vlog, clips: [Fixtures.clip("m_1", at: 0)], preset: presets[.vlog])
        request.destination.city = nil
        request.startDate = "not a date"
        let spec = plan(request)
        XCTAssertEqual(spec.title.text, "Japan")
        XCTAssertNil(spec.title.subtitle)
    }
}
