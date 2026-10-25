//
//  BuildSetting.swift
//  Roamory
//

import Foundation

/// Numbers from the build settings (`Config/Roamory.xcconfig`, passed through Info.plist).
nonisolated enum BuildSetting {
    /// The number under `key`, or `fallback` when it is missing, always inside `range` so a typo cannot break the app.
    static func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        let value = (Bundle.main.infoDictionary?[key] as? String).flatMap(Double.init) ?? fallback
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
