import Foundation
import os

/// A moment that detection decided to keep (TRD §6).
public struct KeptMoment: Sendable, Equatable {
    public let id: String
    public let source: MomentSource
    public let triggerMs: Int
    public let tripId: String

    public init(id: String, source: MomentSource, triggerMs: Int, tripId: String) {
        self.id = id
        self.source = source
        self.triggerMs = triggerMs
        self.tripId = tripId
    }
}

/// The ring buffer's one-step save (TRD §5.5): `startSaving` writes the buffer out and returns the seconds of
/// footage before the call that the file starts with; `stopSaving` closes the file and empties the buffer.
public protocol ClipRecorder: Sendable {
    func startSaving() async throws -> TimeInterval
    func stopSaving() async throws -> URL
}

/// Saves a kept moment as `clips/{id}.mp4` next to a sidecar (TRD §5.5). An actor, so saves run one at a time.
public actor OneStepSaver {
    private let recorder: ClipRecorder
    private let tripFolder: URL
    private let sessionId: String
    private let clock: @Sendable () -> Int
    private let retryDelay: Duration
    private let inspect: @Sendable (URL) async throws -> (durationS: Double, hasAudio: Bool)
    private let log = Logger(subsystem: "com.roamory.Roamory", category: "clips")

    /// - Parameters:
    ///   - clock: the trip clock in ms. It is read right after the buffer is written out, because a save can wait
    ///     behind another one and `fromMs` must match the instant the preroll was measured.
    ///   - retryDelay: how long to wait before the one retry when the buffer cannot be written out
    ///     (a manual save is running, or capture was interrupted and the buffer is empty).
    ///   - inspect: the finished file's duration and whether it has an audio track.
    public init(
        recorder: ClipRecorder, tripFolder: URL, sessionId: String, clock: @escaping @Sendable () -> Int,
        retryDelay: Duration = .seconds(3),
        inspect: @escaping @Sendable (URL) async throws -> (durationS: Double, hasAudio: Bool)
    ) {
        self.recorder = recorder
        self.tripFolder = tripFolder
        self.sessionId = sessionId
        self.clock = clock
        self.retryDelay = retryDelay
        self.inspect = inspect
    }

    public func save(_ moment: KeptMoment) async -> Result<URL, Error> {
        do {
            let (preroll, savedAtMs) = try await begin(moment)
            let temp = try await recorder.stopSaving()
            defer { try? FileManager.default.removeItem(at: temp) }

            let clips = tripFolder.appending(path: "clips")
            try FileManager.default.createDirectory(at: clips, withIntermediateDirectories: true)
            let clip = clips.appending(path: "\(moment.id).mp4")
            try? FileManager.default.removeItem(at: clip)
            try FileManager.default.moveItem(at: temp, to: clip)

            let info = try await inspect(clip)
            let sidecar = OneStepSidecar.make(
                momentId: moment.id, tripId: moment.tripId, sessionId: sessionId, source: moment.source,
                triggerMs: moment.triggerMs, savedAtMs: savedAtMs, prerollS: preroll,
                durationS: info.durationS, hasAudio: info.hasAudio
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sidecar).write(to: clips.appending(path: "\(moment.id).json"), options: .atomic)

            log.info("saved \(moment.id, privacy: .public) preroll=\(preroll) duration=\(info.durationS)")
            return .success(clip)
        } catch {
            log.error("save failed \(moment.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// Writes the buffer out, retrying once. `stopSaving` is never called after a failed start.
    private func begin(_ moment: KeptMoment) async throws -> (preroll: TimeInterval, savedAtMs: Int) {
        do {
            let preroll = try await recorder.startSaving()
            return (preroll, clock())
        } catch {
            log.info("start failed for \(moment.id, privacy: .public), retrying: \(error.localizedDescription, privacy: .public)")
            try await Task.sleep(for: retryDelay)
            let preroll = try await recorder.startSaving()
            return (preroll, clock())
        }
    }
}
