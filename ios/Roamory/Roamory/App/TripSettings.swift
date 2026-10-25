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
        static let lengthHours = "detection.lengthHours"
        static let details = "detection.details"
    }

    static func style(_ defaults: UserDefaults = .standard) -> Style {
        defaults.string(forKey: Key.style).flatMap(Style.init(rawValue:)) ?? .cinematic
    }

    /// Today's planned filming time. Old day-based settings use a separate key.
    static func lengthHours(_ defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: Key.lengthHours) != nil else { return 3 }
        return min(max(defaults.integer(forKey: Key.lengthHours), 1), 24)
    }

    /// Longest note the details step accepts.
    static let detailsLimit = 500

    /// The optional note from the last onboarding step, or nil when it was left empty.
    static func details(_ defaults: UserDefaults = .standard) -> String? {
        let text = defaults.string(forKey: Key.details)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.flatMap { $0.isEmpty ? nil : $0 }
    }
}
