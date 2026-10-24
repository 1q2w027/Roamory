//
//  MomentClipStore.swift
//  Roamory
//

import Foundation
import RoamoryKit

/// Saves kept moments as `clips/{momentId}.mp4` plus a `clips/{momentId}.json` sidecar in the trip folder
/// (TRD 5.3, 5.4), cutting the footage out of the ring buffer. The sidecar is written last, so a clip without
/// one is partial.
nonisolated final class MomentClipStore: Sendable {
    let folder: URL
    private let recorder: RollingRecorder
    private let tripId: String
    private let clock: TripClock
    /// One recording session per trip until pause and resume exist.
    private let sessionId = "s_1"
    /// Capture runs at a fixed 30 fps (TRD 4.1).
    private let fps = 30.0

    init(recorder: RollingRecorder, tripId: String, clock: TripClock, folder: URL? = nil) {
        self.recorder = recorder
        self.tripId = tripId
        self.clock = clock
        self.folder = folder ?? Self.tripFolder(tripId)
    }

    /// `Documents/trips/{tripId}`.
    static func tripFolder(_ tripId: String) -> URL {
        URL.documentsDirectory.appending(path: "trips/\(tripId)", directoryHint: .isDirectory)
    }

    /// Writes the moment's window from the buffer and returns the mp4's URL.
    func save(momentId: String, source: MomentSource, triggerMs: Int, window: MomentWindow) async throws -> URL {
        let clips = folder.appending(path: "clips", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
        let saved = try await recorder.writeClip(from: clock.bufferTime(atMs: window.fromMs),
                                                 to: clock.bufferTime(atMs: window.toMs),
                                                 url: clips.appending(path: "\(momentId).mp4"))
        let fromMs = clock.tripMs(atBufferTime: saved.start)
        let toMs = clock.tripMs(atBufferTime: saved.end)
        guard toMs > fromMs else {
            // A single frame is not a clip.
            try? FileManager.default.removeItem(at: saved.url)
            throw RollingRecorder.RecorderError.footageGone
        }
        let sidecar = ClipSidecar(momentId: momentId, tripId: tripId, sessionId: sessionId, source: source,
                                  triggerMs: triggerMs, fromMs: fromMs, toMs: toMs, hasAudio: saved.hasAudio, fps: fps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(sidecar).write(to: clips.appending(path: "\(momentId).json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: saved.url)
            throw error
        }
        return saved.url
    }
}
