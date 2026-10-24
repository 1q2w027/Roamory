import Foundation

/// Files shipped in `Resources/` (copied from contracts by `scripts/sync-contracts.sh`).
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

    /// Short clips the style picker plays as previews.
    public static var sampleClipURLs: [URL] {
        (Bundle.module.urls(forResourcesWithExtension: "mp4", subdirectory: "Resources/SampleClips") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
