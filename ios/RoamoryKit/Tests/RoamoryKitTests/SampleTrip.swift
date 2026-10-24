import AVFoundation
import Foundation
@testable import RoamoryKit

/// Test inputs: a trip, and `ClipInfo`s from plain .mp4 files such as the bundled sample clips.
enum SampleTrip {
    static let trip = TripContext(
        tripId: "t_sample", style: .cinematic, tripType: "friends", destination: Destination(country: "Japan", city: "Kyoto"),
        startDate: "2026-10-12", allowCloudAnalysis: false
    )

    /// A clip for a file without a sidecar: trigger in the middle, full frame rate, no Stage 1 samples.
    static func clipInfo(file: URL, momentId: String, source: MomentSource, score: Double?, fromMs: Int) async throws -> ClipInfo {
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration).seconds
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        return ClipInfo(
            momentId: momentId, source: source, score: score, fromMs: fromMs, toMs: fromMs + Int(duration * 1000),
            triggerS: duration / 2, clipURL: file, durationS: duration, hasAudio: hasAudio
        )
    }

    /// `count` clips cycling through `files`, one every 5 trip minutes. Every fourth is a button moment.
    static func clips(count: Int, from files: [URL]) async throws -> [ClipInfo] {
        guard !files.isEmpty else { return [] }
        var clips: [ClipInfo] = []
        for i in 0..<count {
            clips.append(try await clipInfo(
                file: files[i % files.count], momentId: String(format: "lab_%02d", i),
                source: i % 4 == 1 ? .button : .ai, score: i % 4 == 1 ? nil : 0.9 - Double(i) * 0.03, fromMs: i * 300_000
            ))
        }
        return clips
    }
}
