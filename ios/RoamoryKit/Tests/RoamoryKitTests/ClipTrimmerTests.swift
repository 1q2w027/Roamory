import AVFoundation
import XCTest
@testable import RoamoryKit

final class ClipTrimmerTests: XCTestCase {
    private let workDir = FileManager.default.temporaryDirectory.appending(path: "ClipTrimmerTests-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
    }

    func testWholeReencodesEachClipUncut() async throws {
        let clips = try await SampleTrip.clips(count: 2, from: BundledResources.sampleClipURLs)
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
