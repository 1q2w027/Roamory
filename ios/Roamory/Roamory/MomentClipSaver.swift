//
//  MomentClipSaver.swift
//  Roamory
//

import AVFoundation
import RoamoryKit
import os

/// A moment that detection decided to keep (TRD §6).
nonisolated struct KeptMoment: Sendable {
    let id: String
    let source: MomentSource
    let triggerMs: Int
    let tripId: String
}

/// Saves a kept moment with the ring buffer's one-step `start()`/`stop()` (TRD §5.5): the buffered footage
/// becomes `clips/{id}.mp4` next to a sidecar. An actor, so saves run one at a time.
actor MomentClipSaver {
    private let recorder: RollingRecorder
    private let tripFolder: URL
    private let sessionId: String
    private let log = Logger(subsystem: "com.roamory.Roamory", category: "clips")

    init(recorder: RollingRecorder, tripFolder: URL, sessionId: String) {
        self.recorder = recorder
        self.tripFolder = tripFolder
        self.sessionId = sessionId
    }

    /// `nowMs` is the trip clock when the keep was decided, which is when the buffer is written out.
    func save(_ moment: KeptMoment, nowMs: Int) async -> Result<URL, Error> {
        do {
            // A manual save in progress also makes `start()` throw `alreadySaving`; no `stop()` then.
            let preroll = try await recorder.start()
            let temp = try await recorder.stop()

            let clips = tripFolder.appending(path: "clips")
            try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
            let clip = clips.appending(path: "\(moment.id).mp4")
            try? FileManager.default.removeItem(at: clip)
            try FileManager.default.moveItem(at: temp, to: clip)

            let asset = AVURLAsset(url: clip)
            let duration = try await asset.load(.duration).seconds
            let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
            let sidecar = OneStepSidecar.make(
                momentId: moment.id, tripId: moment.tripId, sessionId: sessionId, source: moment.source,
                triggerMs: moment.triggerMs, savedAtMs: nowMs, prerollS: preroll, durationS: duration, hasAudio: hasAudio
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sidecar).write(to: clips.appending(path: "\(moment.id).json"), options: .atomic)

            log.info("saved \(moment.id, privacy: .public) preroll=\(preroll) duration=\(duration)")
            return .success(clip)
        } catch {
            log.error("save failed \(moment.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }
}
