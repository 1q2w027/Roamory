import Foundation
import os

/// A trip's files on the phone: `clips/{id}.mp4` with its `clips/{id}.json` sidecar (written last, TRD 5.4), and
/// `moments/{id}.json` with the Stage 2 fields (`MomentFields`). Reading it back gives the editor's input.
public enum TripFolder {
    private static let log = Logger(subsystem: "app.roamory", category: "edit")

    /// Writes `moments/{momentId}.json`.
    public static func saveMoment(_ fields: MomentFields, momentId: String, in folder: URL) throws {
        let moments = folder.appending(path: "moments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: moments, withIntermediateDirectories: true)
        try JSONEncoder().encode(fields).write(to: moments.appending(path: "\(momentId).json"), options: .atomic)
    }

    /// Every complete clip (a readable sidecar whose file exists) with its moment fields, in time order.
    /// Partial and unreadable files are skipped; a clip without a moment file gets empty fields.
    public static func loadClips(in folder: URL) -> [ClipInfo] {
        let clips = folder.appending(path: "clips", directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: clips, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }.compactMap { url -> ClipInfo? in
            guard let sidecar = try? decoder.decode(ClipSidecar.self, from: Data(contentsOf: url)) else {
                log.error("Skipping unreadable sidecar \(url.lastPathComponent, privacy: .public)")
                return nil
            }
            guard FileManager.default.fileExists(atPath: folder.appending(path: sidecar.clipPath).path) else {
                log.error("Skipping \(sidecar.momentId, privacy: .public): its clip file is missing")
                return nil
            }
            let momentURL = folder.appending(path: "moments/\(sidecar.momentId).json")
            let moment = (try? decoder.decode(MomentFields.self, from: Data(contentsOf: momentURL))) ?? MomentFields()
            return ClipInfo(sidecar: sidecar, moment: moment, tripFolder: folder)
        }
        .sorted { ($0.fromMs, $0.momentId) < ($1.fromMs, $1.momentId) }
    }
}
