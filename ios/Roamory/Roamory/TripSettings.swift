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
    }

    static func style(_ defaults: UserDefaults = .standard) -> Style {
        defaults.string(forKey: Key.style).flatMap(Style.init(rawValue:)) ?? .cinematic
    }
}
