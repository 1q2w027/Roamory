import XCTest
@testable import RoamoryKit

@MainActor
final class TripPipelineTests: XCTestCase {
    /// Each test keeps its trip in its own folder, removed when the test object goes away.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "TripPipelineTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func pipeline(_ clips: [ClipInfo], style: Style = .reels) -> TripPipeline {
        var trip = SampleTrip.trip
        trip.style = style
        trip.allowCloudAnalysis = false
        return TripPipeline(trip: trip, folder: folder, clips: clips, planService: nil, remoteRenderer: { _ in nil })
    }

    func testClipsMakeAVideoInTheTripFolder() async throws {
        let clips = try await SampleTrip.clips(count: 2, from: BundledResources.sampleClipURLs)
        let p = pipeline(clips)
        await p.start()

        XCTAssertEqual(p.phase, .editing)
        let c = try XCTUnwrap(p.coordinator)
        XCTAssertEqual(c.phase, .completed)
        let output = try XCTUnwrap(c.video?.outputPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output))
        XCTAssertTrue(output.hasPrefix(folder.appending(path: "video").path))
        XCTAssertFalse(p.isRunning)
    }

    func testNoClipsIsANoMomentsError() async throws {
        let p = pipeline([])
        await p.start()
        XCTAssertEqual(p.coordinator?.phase, .error(stage: .noMoments, message: "No moments were kept on this trip."))
        await p.retry()
        XCTAssertEqual(p.coordinator?.phase, .error(stage: .noMoments, message: "No moments were kept on this trip."))
    }

    func testRerenderUsesTheSameClipsInAnotherStyle() async throws {
        let clips = try await SampleTrip.clips(count: 2, from: BundledResources.sampleClipURLs)
        let p = pipeline(clips, style: .reels)
        await p.start()
        let first = try XCTUnwrap(p.coordinator?.video?.outputPath)

        await p.rerender(style: .cinematic)

        XCTAssertEqual(p.trip.style, .cinematic)
        XCTAssertEqual(p.coordinator?.phase, .completed)
        let second = try XCTUnwrap(p.coordinator?.video?.outputPath)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(p.coordinator?.clips, clips)
    }
}
