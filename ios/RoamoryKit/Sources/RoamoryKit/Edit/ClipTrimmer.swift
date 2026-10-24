import AVFoundation

/// Re-encodes each candidate clip whole for the agent (contracts README, "Agent mode"); the agent chooses the trims.
public enum ClipTrimmer {
    /// One re-encoded file as uploaded.
    public struct Uploaded: Sendable, Equatable {
        public var momentId: String
        public var durationS: Double
        public var hasAudio: Bool

        public init(momentId: String, durationS: Double, hasAudio: Bool) {
            self.momentId = momentId
            self.durationS = durationS
            self.hasAudio = hasAudio
        }
    }

    /// Each clip whole, re-encoded at `presetName` into `{moment_id}.mp4`, in the order of `momentIds`.
    public static func whole(
        _ momentIds: [String], clipURLs: [String: URL], into directory: URL, presetName: String
    ) async throws -> (files: [String: URL], clips: [Uploaded]) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [String: URL] = [:]
        var clips: [Uploaded] = []
        for id in momentIds {
            guard let url = clipURLs[id] else { throw RenderError.missingClip(momentId: id) }
            let (file, exported) = try await export(url, momentId: id, into: directory, presetName: presetName)
            files[id] = file
            clips.append(exported)
        }
        return (files, clips)
    }

    /// Exports `url` to `{momentId}.mp4` and reads back its duration and audio.
    private static func export(
        _ url: URL, momentId: String, into directory: URL, presetName: String
    ) async throws -> (URL, Uploaded) {
        let output = directory.appending(path: "\(momentId).mp4")
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: presetName) else {
            throw RenderError.cannotExport("no export session for preset \(presetName)")
        }
        try await session.export(to: output, as: .mp4)

        let exported = AVURLAsset(url: output)
        let duration = try await exported.load(.duration).seconds
        let hasAudio = try await !exported.loadTracks(withMediaType: .audio).isEmpty
        return (output, Uploaded(momentId: momentId, durationS: duration, hasAudio: hasAudio))
    }
}
