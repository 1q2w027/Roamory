import RoamoryKit
import SwiftUI

/// What onboarding asks, stored per device so each launch starts from the last trip's answers.
enum TripSettings {
    enum Key {
        static let style = "detection.style"
        static let tripType = "detection.tripType"
        static let country = "detection.country"
        static let city = "detection.city"
        static let continent = "detection.continent"
        static let lengthDays = "detection.lengthDays"
        static let details = "detection.details"
    }

    static func style(_ defaults: UserDefaults = .standard) -> Style {
        defaults.string(forKey: Key.style).flatMap(Style.init(rawValue:)) ?? .cinematic
    }

    /// Longest note the details step accepts.
    static let detailsLimit = 500

    /// The optional note from the last onboarding step, or nil when it was left empty.
    static func details(_ defaults: UserDefaults = .standard) -> String? {
        let text = defaults.string(forKey: Key.details)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }
}
