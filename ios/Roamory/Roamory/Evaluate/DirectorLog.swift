//
//  DirectorLog.swift
//  Roamory
//

import Combine
import Foundation

/// What each director request sent and got back, with how long the call took, for the debug log. Only debug builds
/// keep it, because it holds the frames.
final class DirectorLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        /// The JPEGs sent, oldest first.
        let frames: [Data]
        let system: String
        let prompt: String
        let wasSaving: Bool
        /// Wall-clock time of the API call, measured on the phone.
        var seconds: Double = 0
        var raw: String?
        var decision: Director.Decision?
        /// What the app did with the decision: "started saving", "stopped saving", "kept saving", "not saving".
        var applied: String?
        var usage: AnthropicAPI.Usage?
        var error: String?
    }

    private static let limit = 60

    @Published private(set) var entries: [Entry] = []

    /// Writes every entry, oldest first, to a zip with `log.json` and the frames each request sent, and returns it.
    func exportArchive() throws -> URL {
        let fm = FileManager.default
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = fm.temporaryDirectory.appending(path: "director-log-\(stamp)")
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder.appending(path: "frames"), withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        var rows: [[String: Any]] = []
        for (n, entry) in entries.reversed().enumerated() {
            var names: [String] = []
            for (k, jpeg) in entry.frames.enumerated() {
                let name = String(format: "frames/%03d_%d.jpg", n + 1, k + 1)
                try jpeg.write(to: folder.appending(path: name))
                names.append(name)
            }
            var row: [String: Any] = [
                "index": n + 1, "time": iso.string(from: entry.time), "api_seconds": entry.seconds,
                "was_saving": entry.wasSaving, "system_prompt": entry.system, "prompt": entry.prompt, "frames": names,
            ]
            if let decision = entry.decision {
                row["action"] = decision.action.rawValue
                row["summary"] = decision.summary
                row["why"] = decision.why
            }
            if let applied = entry.applied { row["applied"] = applied }
            if let raw = entry.raw { row["raw_reply"] = raw }
            if let error = entry.error { row["error"] = error }
            if let u = entry.usage {
                row["tokens"] = ["input": u.input, "output": u.output, "cache_read": u.cacheRead, "cache_write": u.cacheWrite]
            }
            rows.append(row)
        }
        let json = try JSONSerialization.data(withJSONObject: ["entries": rows], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: folder.appending(path: "log.json"))

        // Reading a folder "for uploading" makes the system hand back a zip of it.
        var coordinationError: NSError?
        var zip: URL?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            let destination = fm.temporaryDirectory.appending(path: folder.lastPathComponent + ".zip")
            try? fm.removeItem(at: destination)
            if (try? fm.copyItem(at: zipped, to: destination)) != nil { zip = destination }
        }
        try? fm.removeItem(at: folder)
        if let zip { return zip }
        throw coordinationError ?? CocoaError(.fileWriteUnknown)
    }

    func record(_ entry: Entry) {
        #if DEBUG
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        let result = entry.decision.map { "\($0.action.rawValue) (\($0.why))" } ?? "error: \(entry.error ?? "?")"
        print(String(format: "[director] %.1f s, %d frames: ", entry.seconds, entry.frames.count) + result)
        #endif
    }
}
