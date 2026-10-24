import AVFoundation

/// Cuts each spec clip's `[in_s, out_s]` into its own file for the render service (contracts README, "Render request rules").
/// It re-encodes, so cuts are frame-exact; passthrough would snap to the 2 s keyframes.
public enum ClipTrimmer {
    public struct Trimmed: Sendable {
        /// Rebased onto `files`.
        public var spec: EditSpec
        public var files: [String: URL]
        public var clips: [RenderRequest.Clip]
    }

    /// Exports one `{moment_id}.mp4` per spec clip into `directory` with `presetName`.
    public static func trim(
        _ spec: EditSpec, clipURLs: [String: URL], into directory: URL, presetName: String
    ) async throws -> Trimmed {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        var clips: [RenderRequest.Clip] = []
        for clip in spec.clips {
            guard let url = clipURLs[clip.momentId] else { throw RenderError.missingClip(momentId: clip.momentId) }
            let range = CMTimeRange(start: CompositionBuilder.time(clip.inS), end: CompositionBuilder.time(clip.outS))
            let (file, exported) = try await export(url, momentId: clip.momentId, range: range, into: directory, presetName: presetName)
            files[clip.momentId] = file
            clips.append(exported)
        }
        let durations = Dictionary(clips.map { ($0.momentId, $0.durationS) }, uniquingKeysWith: { first, _ in first })
        return Trimmed(spec: rebased(spec, durations: durations), files: files, clips: clips)
    }

    /// Agent mode (contracts README, "Agent mode"): each clip whole, re-encoded at `presetName` into `{moment_id}.mp4`,
    /// in the order of `momentIds`. The agent chooses the trims, so nothing is cut.
    public static func whole(
        _ momentIds: [String], clipURLs: [String: URL], into directory: URL, presetName: String
    ) async throws -> (files: [String: URL], clips: [RenderRequest.Clip]) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        var clips: [RenderRequest.Clip] = []
        for id in momentIds {
            guard let url = clipURLs[id] else { throw RenderError.missingClip(momentId: id) }
            let (file, exported) = try await export(url, momentId: id, range: nil, into: directory, presetName: presetName)
            files[id] = file
            clips.append(exported)
        }
        return (files, clips)
    }

    /// Exports `range` of `url` (all of it when nil) to `{momentId}.mp4` and reads back its duration and audio.
    private static func export(
        _ url: URL, momentId: String, range: CMTimeRange?, into directory: URL, presetName: String
    ) async throws -> (URL, RenderRequest.Clip) {
        let output = directory.appending(path: "\(momentId).mp4")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: presetName) else {
            throw RenderError.cannotExport("no export session for preset \(presetName)")
        }
        if let range { session.timeRange = range }
        try await session.export(to: output, as: .mp4)

        let exported = AVURLAsset(url: output)
        let duration = try await exported.load(.duration).seconds
        let hasAudio = try await !exported.loadTracks(withMediaType: .audio).isEmpty
        return (output, RenderRequest.Clip(momentId: momentId, durationS: duration, hasAudio: hasAudio))
    }

    /// Each clip starts at 0 of its trimmed file: `in_s = 0`, `out_s = out_s − in_s`, capped at the file's
    /// actual duration in case the export came out a frame short. Everything else stays, so the timeline does too.
    public static func rebased(_ spec: EditSpec, durations: [String: Double]) -> EditSpec {
        var rebased = spec
        for i in rebased.clips.indices {
            let clip = rebased.clips[i]
            rebased.clips[i].inS = 0
            rebased.clips[i].outS = min(clip.outS - clip.inS, durations[clip.momentId] ?? .infinity)
        }
        return rebased
    }
}
