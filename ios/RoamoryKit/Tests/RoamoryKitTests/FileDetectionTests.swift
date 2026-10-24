import XCTest
@testable import RoamoryKit

final class FileDetectionTests: XCTestCase {
    private func detector(_ holder: CollectingHolder) throws -> MomentDetector {
        let trip = TripInfo(tripId: "t_test", installId: "i_test", style: .cinematic, tripType: "friends",
                            destination: .init(continent: nil, country: "Japan", city: "Kyoto"), lengthDays: 1)
        return MomentDetector(trip: trip, config: try DetectionConfig.bundled(), holder: holder, evaluator: nil,
                              cloudAllowed: false, momentIdPrefix: "m")
    }

    func testSamplesAtTheIntervalAndHoldsButtonPresses() async throws {
        let config = try DetectionConfig.bundled()
        let holder = CollectingHolder()
        let detector = try detector(holder)
        let video = try XCTUnwrap(BundledResources.sampleClipURLs.first)
        let progress = ProgressLog()

        // The second press is after the last frame: it still goes in, at the end.
        let samples = try await FileDetection.detect(
            video: video, buttonPressesMs: [100_000, 3_000], detector: detector, config: config,
            waitForRequests: false, progress: { progress.append($0) }
        )

        XCTAssertGreaterThan(samples.count, 2)
        XCTAssertEqual(samples.first?.tMs, 0)
        for (a, b) in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.tMs - a.tMs, Int(config.sampleIntervalS * 1000) - 50)
        }
        let buttons = await holder.holds.filter { $0.source == .button }
        XCTAssertEqual(buttons.map(\.triggerMs), [3_000, 100_000])
        for hold in buttons {
            let decision = await detector.finalDecision(for: hold.momentId)
            XCTAssertEqual(decision, .keep(source: .button, eventType: nil, description: nil, score: nil))
        }
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertEqual(progress.values, progress.values.sorted())
    }

    func testAFileWithoutVideoThrows() async throws {
        let holder = CollectingHolder()
        let audio = try XCTUnwrap(BundledResources.musicURL(track: "cinematic_01"))
        do {
            try await FileDetection.detect(video: audio, detector: try detector(holder), config: try DetectionConfig.bundled(),
                                           waitForRequests: false)
            XCTFail("expected noVideoTrack")
        } catch {
            XCTAssertEqual(error as? FileDetection.Error, .noVideoTrack)
        }
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Double] = []
    var values: [Double] { lock.withLock { _values } }
    func append(_ value: Double) { lock.withLock { _values.append(value) } }
}
