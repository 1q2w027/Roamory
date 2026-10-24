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
            let output = directory.appending(path: "\(clip.momentId).mp4")
            try? FileManager.default.removeItem(at: output)
            let asset = AVURLAsset(url: url)
            guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
                throw RenderError.cannotExport("no export session for preset \(presetName)")
            }
            session.timeRange = CMTimeRange(start: CompositionBuilder.time(clip.inS), end: CompositionBuilder.time(clip.outS))
            try await session.export(to: output, as: .mp4)

            let trimmed = AVURLAsset(url: output)
            let duration = try await trimmed.load(.duration).seconds
            let hasAudio = try await !trimmed.loadTracks(withMediaType: .audio).isEmpty
            files[clip.momentId] = output
            clips.append(RenderRequest.Clip(momentId: clip.momentId, durationS: duration, hasAudio: hasAudio))
        }
        let durations = Dictionary(clips.map { ($0.momentId, $0.durationS) }, uniquingKeysWith: { first, _ in first })
        return Trimmed(spec: rebased(spec, durations: durations), files: files, clips: clips)
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
