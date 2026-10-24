import Foundation

/// Settings for the on-phone edit from the bundled `edit_config.json` (config, not code).
public struct EditConfig: Codable, Sendable, Equatable {
    public var endCardText: String
    /// `AVAssetExportSession` preset name.
    public var exportPreset: String
    /// Allowed difference between the exported and the planned duration.
    public var renderDurationToleranceS: Double

    enum CodingKeys: String, CodingKey {
        case endCardText = "end_card_text"
        case exportPreset = "export_preset"
        case renderDurationToleranceS = "render_duration_tolerance_s"
    }

    public static func bundled() throws -> EditConfig {
        try BundledResources.decode(EditConfig.self, named: "edit_config")
    }
}
