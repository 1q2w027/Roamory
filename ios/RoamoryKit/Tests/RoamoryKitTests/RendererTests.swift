import AVFoundation
import XCTest
@testable import RoamoryKit

/// Renders the bundled sample clips with the on-phone planner.
final class RendererTests: XCTestCase {
    private var presets: StylePresets!
    private var config: EditConfig!
    private var outputDir: URL!

    override func setUpWithError() throws {
        presets = try StylePresets.bundled()
        config = try EditConfig.bundled()
        outputDir = FileManager.default.temporaryDirectory.appending(path: "RendererTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputDir)
    }

    /// `count` clips cycling through the sample files.
    private func plan(_ style: Style, clips count: Int) async throws -> (EditSpec, [String: URL]) {
        let files = BundledResources.sampleClipURLs
        var clips: [LocalPlanner.Clip] = []
        var urls: [String: URL] = [:]
        for i in 0..<count {
            let file = files[i % files.count]
            let id = String(format: "c_%02d", i)
            clips.append(LocalPlanner.Clip(id: id, durationS: try await AVURLAsset(url: file).load(.duration).seconds))
            urls[id] = file
        }
        let spec = LocalPlanner.plan(
            tripId: "t_sample", style: style, preset: presets[style], clips: clips, title: "Kyoto", subtitle: "October 2026",
            endCardText: config.endCardText
        )
        return (spec, urls)
    }

    private func assertRendered(_ result: RenderResult, _ spec: EditSpec, file: StaticString = #filePath, line: UInt = #line) async throws {
        let asset = AVURLAsset(url: result.url)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable, file: file, line: line)
        XCTAssertEqual(result.durationS, EditTimeline.totalDurationS(result.spec), accuracy: 0.5, file: file, line: line)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first, file: file, line: line)
        let size = try await video.load(.naturalSize)
        XCTAssertEqual(Int(size.width), spec.output.width, file: file, line: line)
        XCTAssertEqual(Int(size.height), spec.output.height, file: file, line: line)
        let format = try await video.load(.formatDescriptions).first
        XCTAssertEqual(format?.mediaSubType, .h264, "H.264", file: file, line: line)
    }

    func testEveryPresetRendersThreeClips() async throws {
        for style in Style.allCases {
            let (spec, urls) = try await plan(style, clips: 3)
            let result = try await Renderer(config: config).render(spec, clipURLs: urls, to: outputDir.appending(path: "\(style).mp4"))
            try await assertRendered(result, spec)
            XCTAssertFalse(result.usedHardCutRetry, "\(style)")
        }
    }

    func testOneAndTenClips() async throws {
        // Vlog keeps original audio; its one clip (sample_a) has none.
        for (style, count) in [(Style.reels, 1), (.documentary, 10), (.vlog, 1)] {
            let (spec, urls) = try await plan(style, clips: count)
            let result = try await Renderer(config: config).render(spec, clipURLs: urls, to: outputDir.appending(path: "\(count).mp4"))
            try await assertRendered(result, spec)
        }
    }

    func testVlogKeepsOriginalAudio() async throws {
        let (spec, urls) = try await plan(.vlog, clips: 4)
        XCTAssertFalse(spec.music.duckOriginalAudio)
        let result = try await Renderer(config: config).render(spec, clipURLs: urls, to: outputDir.appending(path: "vlog.mp4"))
        try await assertRendered(result, spec)
        let audio = try await AVURLAsset(url: result.url).loadTracks(withMediaType: .audio)
        XCTAssertFalse(audio.isEmpty)
    }

    func testSpeedRampChangesTheLength() async throws {
        let (planned, urls) = try await plan(.reels, clips: 3)
        var spec = planned
        spec.clips[0].speedRamp = EditSpec.SpeedRamp(from: 4, to: 1, overS: 1)
        let result = try await Renderer(config: config).render(spec, clipURLs: urls, to: outputDir.appending(path: "ramp.mp4"))
        try await assertRendered(result, spec)
        XCTAssertLessThan(EditTimeline.totalDurationS(spec), EditTimeline.totalDurationS(spec.withHardCuts()) + 1e-9)
    }

    func testFailedExportWithTransitionsRetriesWithHardCuts() async throws {
        let (spec, urls) = try await plan(.cinematic, clips: 3)
        var renderer = Renderer(config: config)
        renderer.simulateTransitionFailure = true
        let result = try await renderer.render(spec, clipURLs: urls, to: outputDir.appending(path: "retry.mp4"))
        XCTAssertTrue(result.usedHardCutRetry)
        XCTAssertTrue(result.spec.clips.allSatisfy { $0.transitionIn == .cut })
        try await assertRendered(result, spec)
    }

    func testMissingClipFails() async throws {
        let (spec, _) = try await plan(.vlog, clips: 2)
        do {
            _ = try await Renderer(config: config).render(spec, clipURLs: [:], to: outputDir.appending(path: "x.mp4"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RenderError, .missingClip(momentId: spec.clips[0].momentId))
        }
    }

    func testAspectFillRotatesAndFills() {
        // 640x360 landscape footage rotated 90 degrees (portrait) into a 1080x1920 frame.
        let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 360, ty: 0)
        let t = CompositionBuilder.aspectFill(preferred: rotate, natural: CGSize(width: 640, height: 360), into: CGSize(width: 1080, height: 1920))
        let rect = CGRect(x: 0, y: 0, width: 640, height: 360).applying(t)
        XCTAssertEqual(rect.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(rect.minY, 0, accuracy: 1e-6)
        XCTAssertEqual(rect.width, 1080, accuracy: 1e-6)
        XCTAssertEqual(rect.height, 1920, accuracy: 1e-6)

        // Landscape into portrait: fills the height and crops the sides evenly.
        let crop = CGRect(x: 0, y: 0, width: 640, height: 360)
            .applying(CompositionBuilder.aspectFill(preferred: .identity, natural: CGSize(width: 640, height: 360), into: CGSize(width: 1080, height: 1920)))
        XCTAssertEqual(crop.height, 1920, accuracy: 1e-6)
        XCTAssertEqual(crop.midX, 540, accuracy: 1e-6)
    }
}
