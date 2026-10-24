import AVFoundation
import XCTest
@testable import RoamoryKit

final class ClipTrimmerTests: XCTestCase {
    private let workDir = FileManager.default.temporaryDirectory.appending(path: "ClipTrimmerTests-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
    }

    func testRebaseStartsEachClipAtZeroAndKeepsTheTimeline() throws {
        let spec = try Fixtures.editSpec(.cinematic)
        let rebased = ClipTrimmer.rebased(spec, durations: [:])
        for (clip, original) in zip(rebased.clips, spec.clips) {
            XCTAssertEqual(clip.inS, 0)
            XCTAssertEqual(clip.outS, original.outS - original.inS, accuracy: 1e-9)
            XCTAssertEqual(clip.speedRamp, original.speedRamp)
            XCTAssertEqual(clip.transitionIn, original.transitionIn)
        }
        XCTAssertEqual(EditTimeline.slots(rebased), EditTimeline.slots(spec))
        XCTAssertEqual(rebased.title, spec.title)
        XCTAssertEqual(rebased.music, spec.music)
    }

    func testRebaseMatchesTheContractExample() throws {
        for style in Style.allCases {
            let example = try Fixtures.decode(RenderRequest.self, "examples/render_request_\(style.rawValue).json")
            let durations = Dictionary(uniqueKeysWithValues: example.clips.map { ($0.momentId, $0.durationS) })
            XCTAssertEqual(ClipTrimmer.rebased(try Fixtures.editSpec(style), durations: durations), example.editSpec, "\(style)")
        }
    }

    func testRebaseCapsAtAShortExport() {
        let spec = EditSpec.Clip(momentId: "m", inS: 10, outS: 12.5, transitionIn: .cut, transitionS: 0, speedRamp: nil, caption: nil)
        var edit = try! Fixtures.editSpec(.reels)
        edit.clips = [spec]
        XCTAssertEqual(ClipTrimmer.rebased(edit, durations: ["m": 2.48]).clips[0].outS, 2.48)
        XCTAssertEqual(ClipTrimmer.rebased(edit, durations: ["m": 2.6]).clips[0].outS, 2.5)
    }

    func testTrimsEachClipToItsRange() async throws {
        let (spec, urls) = try await RemoteRenderClientTests.plan(clips: 2)
        let trimmed = try await ClipTrimmer.trim(spec, clipURLs: urls, into: workDir, presetName: Fixtures.config.remoteUploadPreset)
        XCTAssertEqual(trimmed.clips.map(\.momentId), spec.clips.map(\.momentId))
        for (clip, original) in zip(trimmed.clips, spec.clips) {
            let file = try XCTUnwrap(trimmed.files[clip.momentId])
            XCTAssertEqual(file.lastPathComponent, "\(clip.momentId).mp4")
            XCTAssertEqual(clip.durationS, original.outS - original.inS, accuracy: 0.1, clip.momentId)
            let duration = try await AVURLAsset(url: file).load(.duration).seconds
            XCTAssertEqual(duration, clip.durationS, accuracy: 1e-6)
        }
        XCTAssertTrue(trimmed.spec.clips.allSatisfy { $0.inS == 0 })
        XCTAssertEqual(EditTimeline.totalDurationS(trimmed.spec), EditTimeline.totalDurationS(spec), accuracy: 0.1)
    }

    func testWholeReencodesEachClipUncut() async throws {
        let clips = try await RenderLab.clips(count: 2, from: BundledResources.sampleClipURLs)
        let urls = Dictionary(uniqueKeysWithValues: clips.map { ($0.momentId, $0.clipURL) })
        let whole = try await ClipTrimmer.whole(clips.map(\.momentId), clipURLs: urls, into: workDir,
                                                presetName: Fixtures.config.agentUploadPreset)
        XCTAssertEqual(whole.clips.map(\.momentId), clips.map(\.momentId))
        for (clip, original) in zip(whole.clips, clips) {
            let file = try XCTUnwrap(whole.files[clip.momentId])
            XCTAssertEqual(file.lastPathComponent, "\(clip.momentId).mp4")
            XCTAssertEqual(clip.durationS, original.durationS, accuracy: 0.1, clip.momentId)
            let track = try await AVURLAsset(url: file).loadTracks(withMediaType: .video).first
            let size = try await XCTUnwrap(track).load(.naturalSize)
            XCTAssertLessThanOrEqual(max(size.width, size.height), 1280, "re-encoded at the upload preset")
        }
    }
}
