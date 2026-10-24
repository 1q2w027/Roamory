//
//  MomentClipSaver.swift
//  Roamory
//

import AVFoundation
import Foundation
import RoamoryKit

/// The ring buffer's one-step save, as `OneStepSaver` (RoamoryKit) sees it (TRD §5.5).
extension RollingRecorder: ClipRecorder {
    func startSaving() async throws -> TimeInterval { try await start() }
    func stopSaving() async throws -> URL { try await stop() }
}

/// The trip clock (ms since detection started), readable from any thread.
nonisolated final class TripClock: @unchecked Sendable {
    private let lock = NSLock()
    private var startUptime = ProcessInfo.processInfo.systemUptime

    func start(at uptime: TimeInterval) { lock.withLock { startUptime = uptime } }

    var nowMs: Int { Int((ProcessInfo.processInfo.systemUptime - lock.withLock { startUptime }) * 1000) }
}

extension OneStepSaver {
    /// A saver for the camera's ring buffer, with the file inspected through AVFoundation.
    static func forCamera(recorder: RollingRecorder, tripFolder: URL, sessionId: String, clock: TripClock) -> OneStepSaver {
        OneStepSaver(recorder: recorder, tripFolder: tripFolder, sessionId: sessionId, clock: { clock.nowMs }) { url in
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
            return (duration, hasAudio)
        }
    }
}
