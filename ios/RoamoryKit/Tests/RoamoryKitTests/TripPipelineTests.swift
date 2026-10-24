import XCTest
@testable import RoamoryKit

@MainActor
final class TripPipelineTests: XCTestCase {
    /// Each test keeps its trips in its own folder, removed when the test object goes away.
    private let tripsFolder = FileManager.default.temporaryDirectory.appending(path: "TripPipelineTests-\(UUID().uuidString)")

    deinit {
        try? FileManager.default.removeItem(at: tripsFolder)
    }

    private func pipeline(style: Style = .reels) -> TripPipeline {
        TripPipeline(
            settings: TripSettings(style: style, allowCloudAnalysis: false), tripsFolder: tripsFolder, installId: "i_test",
            evaluator: nil, planService: nil, remoteRenderer: { _ in nil }
        )
    }

    private var sample: URL { BundledResources.sampleClipURLs[0] }

    func testAButtonPressMakesAVideoWithTheMomentMarked() async throws {
        let p = pipeline()
        await p.start(video: sample, buttonPressesMs: [3_000], move: false)

        XCTAssertEqual(p.phase, .editing)
        let c = try XCTUnwrap(p.coordinator)
        XCTAssertEqual(c.phase, .completed)
        XCTAssertEqual(p.clips?.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: p.tripFolder.appending(path: "source.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(c.video?.outputPath)))
        XCTAssertTrue(c.video?.outputPath?.hasPrefix(p.tripFolder.appending(path: "video").path) == true)
        XCTAssertEqual(c.reviewMoments.filter(\.isButton).map(\.momentId), p.clips?.map(\.momentId))
        XCTAssertFalse(p.isRunning)
    }

    func testNoMomentsIsANoMomentsError() async throws {
        // A short sample has no escalations, and nothing was pressed.
        let p = pipeline()
        await p.start(video: sample, move: false)
        XCTAssertEqual(p.clips, [])
        XCTAssertEqual(p.coordinator?.phase, .error(stage: .noMoments, message: "No moments were kept on this trip."))
    }

    func testAnUnreadableRecordingFailsAndRetriesFromTheStart() async throws {
        let notVideo = tripsFolder.appending(path: "not_video.mov")
        try FileManager.default.createDirectory(at: tripsFolder, withIntermediateDirectories: true)
        try Data("not a movie".utf8).write(to: notVideo)
        let p = pipeline()
        await p.start(video: notVideo)

        guard case .failed = p.phase else { return XCTFail("expected a failure, got \(p.phase)") }
        XCTAssertNil(p.clips)
        XCTAssertFalse(FileManager.default.fileExists(atPath: notVideo.path), "the recording moves into the trip")
        await p.retry()
        guard case .failed = p.phase else { return XCTFail("retry should find the moments again") }
    }

    func testRerenderUsesTheSameClipsInAnotherStyle() async throws {
        let p = pipeline(style: .reels)
        await p.start(video: sample, buttonPressesMs: [3_000], move: false)
        let first = try XCTUnwrap(p.coordinator?.video?.outputPath)

        await p.rerender(style: .cinematic)

        XCTAssertEqual(p.trip.style, .cinematic)
        XCTAssertEqual(p.coordinator?.phase, .completed)
        let second = try XCTUnwrap(p.coordinator?.video?.outputPath)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(p.coordinator?.clips, p.clips)
    }

    func testSettingsRoundTripAndFillBlanks() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TripPipelineTests-\(UUID().uuidString)"))
        XCTAssertEqual(TripSettings.load(defaults), TripSettings())
        let settings = TripSettings(style: .vlog, tripType: "family", country: "  ", city: "", lengthDays: 0)
        settings.save(defaults)
        XCTAssertEqual(TripSettings.load(defaults), settings)
        XCTAssertEqual(TripSettings.installId(defaults), TripSettings.installId(defaults))

        let trip = settings.tripContext(tripId: "t_1", startDate: Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertEqual(trip.destination, Destination(country: "Japan", city: nil))
        XCTAssertEqual(trip.startDate.count, 10)
        XCTAssertEqual(settings.tripInfo(tripId: "t_1", installId: "i").lengthDays, 1)
    }
}
