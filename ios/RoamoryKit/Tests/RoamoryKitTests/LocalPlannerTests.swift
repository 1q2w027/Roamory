import XCTest
@testable import RoamoryKit

final class LocalPlannerTests: XCTestCase {
    private func plan(_ style: Style, _ durations: [Double]) throws -> EditSpec {
        let clips = durations.enumerated().map { LocalPlanner.Clip(id: "c_\($0.offset)", durationS: $0.element) }
        return LocalPlanner.plan(
            tripId: "t_test", style: style, preset: try Fixtures.presets()[style], clips: clips,
            title: "Kyoto", subtitle: "October 2026", endCardText: "Made with Roamory"
        )
    }

    func testLongClipsLandNearTheTarget() throws {
        let presets = try Fixtures.presets()
        for style in Style.allCases {
            let spec = try plan(style, [45, 60, 50])
            XCTAssertEqual(EditTimeline.totalDurationS(spec), presets[style].targetS.default, accuracy: presets[style].clipS.default, "\(style)")
            XCTAssertEqual(Set(spec.clips.map(\.momentId)), ["c_0", "c_1", "c_2"], "\(style)")
        }
    }

    func testCutsStayInsideTheirClipInOrder() throws {
        let spec = try plan(.reels, [45, 3, 46])
        var last: (String, Double)?
        for clip in spec.clips {
            let duration = ["c_0": 45.0, "c_1": 3, "c_2": 46][clip.momentId]!
            XCTAssertGreaterThanOrEqual(clip.inS, 0)
            XCTAssertLessThanOrEqual(clip.outS, duration + 0.001)
            if let last, last.0 == clip.momentId { XCTAssertGreaterThanOrEqual(clip.inS, last.1 - 0.001) }
            last = (clip.momentId, clip.outS)
        }
        XCTAssertEqual(spec.clips.map(\.momentId).filter { $0 == "c_1" }.count, 1)
    }

    func testManyClipsTakeOneEachFromAcrossTheTrip() throws {
        let spec = try plan(.documentary, Array(repeating: 45, count: 40))
        XCTAssertLessThan(spec.clips.count, 40)
        XCTAssertEqual(Set(spec.clips.map(\.momentId)).count, spec.clips.count)
        XCTAssertEqual(spec.clips.first?.momentId, "c_2")
        XCTAssertEqual(spec.clips.last?.momentId, "c_38")
    }

    func testTooShortClipsAreSkipped() throws {
        XCTAssertTrue(try plan(.documentary, [1.5, 2]).clips.isEmpty)
        XCTAssertEqual(try plan(.reels, [1.5]).clips.count, 1)
    }
}
