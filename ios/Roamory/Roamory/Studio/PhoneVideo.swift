//
//  PhoneVideo.swift
//  Roamory
//

import Foundation
import RoamoryKit
import UIKit

/// Makes the video on the iPhone with AVFoundation, with no Mac or model: evenly spaced cuts from the trip's clips
/// in the chosen style. The backup when Roamory Studio is not available.
enum PhoneVideo {
    enum Failure: LocalizedError {
        case clipsTooShort

        var errorDescription: String? { "The saved clips are too short for this style." }
    }

    /// Renders into a temporary file and returns it.
    static func make(clips: [TripClip], style: Style, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let presets = try StylePresets.bundled()
        let config = try EditConfig.bundled()
        var planned: [LocalPlanner.Clip] = []
        for clip in clips {
            planned.append(LocalPlanner.Clip(id: clip.id, durationS: try await TripClips.details(of: clip).duration))
        }
        let defaults = UserDefaults.standard
        let city = defaults.string(forKey: TripSettings.Key.city).flatMap { $0.isEmpty ? nil : $0 }
        let spec = LocalPlanner.plan(
            tripId: TripClips.tripID, style: style, preset: presets[style], clips: planned,
            title: city ?? defaults.string(forKey: TripSettings.Key.country) ?? "My trip",
            subtitle: clips.first?.recordedAt.formatted(.dateTime.month(.wide).year()), endCardText: config.endCardText
        )
        guard !spec.clips.isEmpty else { throw Failure.clipsTooShort }

        // Exporting needs the app in the foreground, so keep the screen awake.
        let idle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idle }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(spec.tripId)_\(style.rawValue).mp4")
        let urls = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0.url) })
        return try await Renderer(config: config).render(spec, clipURLs: urls, to: url, progress: progress).url
    }
}
