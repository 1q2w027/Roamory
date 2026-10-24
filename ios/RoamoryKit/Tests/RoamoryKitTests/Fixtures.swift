import Foundation
@testable import RoamoryKit

/// Reads `contracts/` from the repo checkout, so tests use the shared examples directly.
enum Fixtures {
    static let contracts = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent()  // RoamoryKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // RoamoryKit
        .deletingLastPathComponent()  // ios
        .deletingLastPathComponent()  // repo root
        .appending(path: "contracts")

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: contracts.appending(path: path))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(path))
    }

    static func presets() throws -> StylePresets {
        try decode(StylePresets.self, "style_presets.json")
    }

    static let config = try! EditConfig.bundled()
}

/// JSON values compared as Foundation objects, so key order and 30 vs 30.0 don't matter.
func jsonObject(_ data: Data) throws -> NSObject {
    try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as! NSObject
}
