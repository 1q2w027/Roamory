import AVFoundation
import XCTest
@testable import RoamoryKit

final class ClipExtractorTests: XCTestCase {
    let config = try! DetectionConfig.bundled()

    private func kept(_ id: String, _ s: Double, _ source: MomentSource = .ai, score: Double? = nil,
                      description: String? = nil) -> ClipExtractor.Kept {
        .init(momentId: id, triggerMs: Int(s * 1000), source: source,
              fields: MomentFields(description: description, score: score))
    }

    private func spans(_ windows: [ClipExtractor.Window]) -> [[Int]] {
        windows.map { [$0.fromMs / 1000, $0.toMs / 1000] }
    }

    func testWindowsAreClampedToTheRecording() {
        let w = ClipExtractor.windows([kept("a", 5), kept("b", 595)], durationMs: 600_000, config: config)
        XCTAssertEqual(spans(w), [[0, 20], [580, 600]])
    }

    func testOverlapOverFiveSecondsExtendsTheWindow() {
        // 100 → [85, 115]; 120 → [105, 135] overlaps by 10 s.
        let w = ClipExtractor.windows([kept("b", 120), kept("a", 100)], durationMs: 600_000, config: config)
        XCTAssertEqual(spans(w), [[85, 135]])
        XCTAssertEqual(w[0].moment.momentId, "a")
    }

    func testOverlapOfFiveSecondsOrLessStaysSeparate() {
        // 100 → [85, 115]; 125 → [110, 140] overlaps by exactly 5 s.
        let w = ClipExtractor.windows([kept("a", 100), kept("b", 125)], durationMs: 600_000, config: config)
        XCTAssertEqual(spans(w), [[85, 115], [110, 140]])
    }

    func testMergedWindowsStopAtTheCap() {
        // A chain every 10 s from 100 s: one window, capped at 60 s from 85 s.
        let moments = stride(from: 100.0, through: 140, by: 10).enumerated().map { kept("m\($0.offset)", $0.element) }
        let w = ClipExtractor.windows(moments, durationMs: 600_000, config: config)
        XCTAssertEqual(spans(w), [[85, 145]])
    }

    func testATriggerPastTheCapStartsWhereTheLastWindowEnds() {
        // [85, 145] is full; 150 overlaps it by 10 s but lies past the cap.
        let moments = [100.0, 110, 120, 130, 140, 150].enumerated().map { kept("m\($0.offset)", $0.element) }
        let w = ClipExtractor.windows(moments, durationMs: 600_000, config: config)
        XCTAssertEqual(spans(w), [[85, 145], [145, 165]])
        XCTAssertEqual(w[1].moment.momentId, "m5")
    }

    func testAButtonMomentNamesTheMergedWindow() {
        let w = ClipExtractor.windows(
            [kept("ai", 100, score: 0.9, description: "A temple gate"), kept("btn", 108, .button)],
            durationMs: 600_000, config: config
        )
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].moment.momentId, "btn")
        XCTAssertEqual(w[0].moment.source, .button)
        XCTAssertEqual(w[0].moment.triggerMs, 108_000)
        XCTAssertEqual(w[0].moment.fields.score, 0.9)
        XCTAssertEqual(w[0].moment.fields.description, "A temple gate")
    }

    func testExtractWritesClipsAndSidecars() async throws {
        let video = try XCTUnwrap(BundledResources.sampleClipURLs.first)
        let durationMs = Int(try await AVURLAsset(url: video).load(.duration).seconds * 1000)
        let folder = FileManager.default.temporaryDirectory.appending(path: "extract_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let windows = [ClipExtractor.Window(moment: kept("m_1", 4, .button), fromMs: 1_000, toMs: min(9_000, durationMs))]
        let samples = [0, 2_000, 4_000, 6_000, 10_000].map {
            FileDetection.Sample(tMs: $0, sharpness: 100, change: 3, dhash: 0xab)
        }

        let clips = try await ClipExtractor.extract(
            video: video, windows: windows, samples: samples, tripId: "t_1", sessionId: "s_1", tripFolder: folder
        )

        let clip = try XCTUnwrap(clips.first)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clip.clipURL, folder.appending(path: "clips/m_1.mp4"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.clipURL.path))
        XCTAssertEqual(clip.durationS, Double(windows[0].toMs - 1_000) / 1000, accuracy: 0.5)
        XCTAssertEqual(clip.triggerS, 3, accuracy: 0.001)
        XCTAssertTrue(clip.isButton)

        let sidecar = try JSONDecoder().decode(
            ClipSidecar.self, from: Data(contentsOf: folder.appending(path: "clips/m_1.json"))
        )
        XCTAssertEqual(sidecar.clipPath, "clips/m_1.mp4")
        XCTAssertEqual(sidecar.samples.map(\.tS), [1, 3, 5])
        XCTAssertEqual(sidecar.samples.first?.dhash, "00000000000000ab")
        XCTAssertEqual(ClipInfo(sidecar: sidecar, moment: MomentFields(), tripFolder: folder).clipURL, clip.clipURL)
    }

    func testKeptDropsReleasedMoments() async throws {
        let holder = CollectingHolder()
        let trip = TripInfo(tripId: "t", installId: "i", style: .vlog, tripType: "solo",
                            destination: .init(continent: nil, country: "Japan", city: "Kyoto"), lengthDays: 1)
        let detector = MomentDetector(trip: trip, config: config, holder: holder, evaluator: nil, cloudAllowed: false,
                                      momentIdPrefix: "m")
        let button = await detector.buttonPressed(atMs: 5_000)
        let holds = await holder.holds + [.init(momentId: "unknown", triggerMs: 9_000, source: .ai)]

        let kept = await ClipExtractor.kept(holds, detector: detector)
        XCTAssertEqual(kept, [.init(momentId: button, triggerMs: 5_000, source: .button)])
    }
}
