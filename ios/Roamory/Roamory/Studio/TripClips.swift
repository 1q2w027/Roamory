//
//  TripClips.swift
//  Roamory
//

import AVFoundation
import Foundation

/// A clip saved during this trip, kept in the app (as well as in Photos) so Roamory Studio can edit it.
struct TripClip: Codable, Identifiable, Hashable {
    let id: String
    /// When the clip starts: the oldest buffered frame.
    let recordedAt: Date

    var url: URL { TripClips.folder.appendingPathComponent("\(id).mp4") }
}

/// The trip's saved clips, in Application Support/Trip/clips: `<id>.mp4` with a `<id>.json` sidecar.
enum TripClips {
    static let folder = URL.applicationSupportDirectory.appendingPathComponent("Trip/clips", isDirectory: true)
    private static let tripIDKey = "trip.id"

    /// Moves a finished clip into the trip and returns it.
    static func keep(_ file: URL, recordedAt: Date) throws -> TripClip {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let n = all().count + 1
        let clip = TripClip(id: String(format: "c_%02d_%@", n, UUID().uuidString.prefix(6).lowercased() as CVarArg),
                            recordedAt: recordedAt)
        try FileManager.default.moveItem(at: file, to: clip.url)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(clip).write(to: folder.appendingPathComponent("\(clip.id).json"))
        return clip
    }

    /// Oldest first.
    static func all() -> [TripClip] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(TripClip.self, from: Data(contentsOf: $0)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    /// Deletes the clips (Photos keeps its copies) and starts a new trip id.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removeObject(forKey: tripIDKey)
    }

    /// Stays the same until the clips are deleted.
    static var tripID: String {
        if let id = UserDefaults.standard.string(forKey: tripIDKey) { return id }
        let id = "t_" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(id, forKey: tripIDKey)
        return id
    }

    /// Duration and whether the file has sound, read from the file.
    static func details(of clip: TripClip) async throws -> (duration: Double, hasAudio: Bool) {
        let asset = AVURLAsset(url: clip.url)
        let duration = try await asset.load(.duration).seconds
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        return (duration, hasAudio)
    }
}
