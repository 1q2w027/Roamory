import AVFoundation
import Foundation

/// Cuts a finished recording into `clips/{moment_id}.mp4` plus sidecar JSON for every kept moment (TRD 5.3),
/// standing in for the rolling buffer: the edit pipeline then reads them like any finalized clip.
public enum ClipExtractor {
    public enum Error: Swift.Error, Equatable {
        case cannotExport(String)
    }

    /// A moment the detector kept.
    public struct Kept: Sendable, Equatable {
        public var momentId: String
        /// From the recording's start.
        public var triggerMs: Int
        public var source: MomentSource
        public var fields: MomentFields

        public init(momentId: String, triggerMs: Int, source: MomentSource, fields: MomentFields = .init()) {
            self.momentId = momentId
            self.triggerMs = triggerMs
            self.source = source
            self.fields = fields
        }
    }

    /// The span of the recording one clip covers; merged moments share one.
    public struct Window: Sendable, Equatable {
        /// The moment the clip is named after: a button moment when the window has one.
        public var moment: Kept
        public var fromMs: Int
        public var toMs: Int
    }

    /// Asks the detector for each hold's final decision and returns the kept ones.
    public static func kept(_ holds: [CollectingHolder.Hold], detector: MomentDetector) async -> [Kept] {
        var kept: [Kept] = []
        for hold in holds {
            guard case let .keep(source, eventType, description, score) = await detector.finalDecision(for: hold.momentId)
            else { continue }
            kept.append(Kept(momentId: hold.momentId, triggerMs: hold.triggerMs, source: source,
                             fields: MomentFields(eventType: eventType, description: description, score: score)))
        }
        return kept
    }

    /// [trigger − pre, trigger + post] inside the recording. A window that overlaps the previous one by more than
    /// `merge_overlap_s` extends it, up to `max_clip_s` (TRD 5.3 rule 4); past the cap it starts where that one ends.
    public static func windows(_ kept: [Kept], durationMs: Int, config: DetectionConfig) -> [Window] {
        let preMs = Int(config.preS * 1000), postMs = Int(config.postS * 1000)
        let mergeMs = Int(config.mergeOverlapS * 1000), maxMs = Int(config.maxClipS * 1000)
        var windows: [Window] = []
        for moment in kept.sorted(by: { $0.triggerMs < $1.triggerMs }) {
            let t = min(max(moment.triggerMs, 0), durationMs)
            var next = Window(moment: moment, fromMs: max(t - preMs, 0), toMs: min(t + postMs, durationMs))
            if var last = windows.last, last.toMs - next.fromMs > mergeMs {
                let capEnd = last.fromMs + maxMs
                if t <= capEnd {
                    last.toMs = min(max(last.toMs, next.toMs), capEnd)
                    last.moment = merged(last.moment, moment)
                    windows[windows.count - 1] = last
                    continue
                }
                next.fromMs = last.toMs
            }
            windows.append(next)
        }
        return windows.filter { $0.toMs > $0.fromMs }
    }

    /// Button beats AI beats local fallback, then the higher score; the other fills in missing text.
    static func merged(_ a: Kept, _ b: Kept) -> Kept {
        func rank(_ k: Kept) -> (Int, Double) {
            (k.source == .button ? 2 : k.source == .ai ? 1 : 0, k.fields.score ?? -1)
        }
        var (primary, other) = rank(b) > rank(a) ? (b, a) : (a, b)
        primary.fields.eventType = primary.fields.eventType ?? other.fields.eventType
        primary.fields.description = primary.fields.description ?? other.fields.description
        primary.fields.score = [primary.fields.score, other.fields.score].compactMap { $0 }.max()
        return primary
    }

    /// Exports each window from `video` into `tripFolder/clips/`, writes its sidecar, and returns the clips in
    /// trip order. Cuts are passthrough, so they may snap to a nearby keyframe (TRD 5.3 rule 5); the planner trims.
    /// - Parameter samples: from `FileDetection.detect`, copied into each sidecar.
    public static func extract(
        video: URL, windows: [Window], samples: [FileDetection.Sample], tripId: String, sessionId: String, tripFolder: URL
    ) async throws -> [ClipInfo] {
        let clipsFolder = tripFolder.appending(path: "clips")
        try FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: video)
        let fps = try await asset.loadTracks(withMediaType: .video).first?.load(.nominalFrameRate) ?? 30
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var clips: [ClipInfo] = []
        for window in windows {
            let id = window.moment.momentId
            let clipPath = "clips/\(id).mp4"
            let output = tripFolder.appending(path: clipPath)
            try? FileManager.default.removeItem(at: output)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw Error.cannotExport("no passthrough export session")
            }
            session.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(window.fromMs), timescale: 1000),
                                            end: CMTime(value: CMTimeValue(window.toMs), timescale: 1000))
            try await session.export(to: output, as: .mp4)

            let clip = AVURLAsset(url: output)
            let durationS = try await clip.load(.duration).seconds
            let hasAudio = try await !clip.loadTracks(withMediaType: .audio).isEmpty
            let toMs = window.fromMs + Int((durationS * 1000).rounded())
            let sidecar = ClipSidecar(
                version: 1, momentId: id, tripId: tripId, sessionId: sessionId, source: window.moment.source,
                triggerMs: window.moment.triggerMs, fromMs: window.fromMs, toMs: toMs, clipPath: clipPath,
                durationS: durationS, hasAudio: hasAudio, fpsProfile: [.init(tS: 0, fps: Double(fps > 0 ? fps : 30))],
                samples: samples.filter { $0.tMs >= window.fromMs && $0.tMs <= toMs }.map {
                    .init(tS: Double($0.tMs - window.fromMs) / 1000, sharpness: $0.sharpness, change: $0.change,
                          dhash: String(format: "%016llx", $0.dhash))
                }
            )
            try encoder.encode(sidecar).write(to: clipsFolder.appending(path: "\(id).json"))
            clips.append(ClipInfo(sidecar: sidecar, moment: window.moment.fields, tripFolder: tripFolder))
        }
        return clips
    }
}
