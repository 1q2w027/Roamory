import Foundation

/// Files shipped in `Resources/` (presets copied from contracts by `scripts/sync-contracts.sh`).
public enum BundledResources {
    public static func url(_ name: String, ext: String, subdirectory: String? = nil) -> URL? {
        let dir = ["Resources", subdirectory].compactMap(\.self).joined(separator: "/")
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: dir)
    }

    static func decode<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        guard let url = url(name, ext: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Resources/\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    /// The music bed each style's preset names, for the on-phone renderer.
    public static func musicURL(track: String) -> URL? { url(track, ext: "m4a", subdirectory: "Music") }

    /// The 2 s black clip the end card plays over.
    public static func blackClipURL(portrait: Bool) -> URL? { url(portrait ? "black_9x16" : "black_16x9", ext: "mp4") }

    /// Short clips the style picker plays as previews.
    public static var sampleClipURLs: [URL] {
        (Bundle.module.urls(forResourcesWithExtension: "mp4", subdirectory: "Resources/SampleClips") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
