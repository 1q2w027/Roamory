//
//  SummarySettings.swift
//  Roamory
//

import Foundation
import FoundationModels

/// Which model describes the buffer when Evaluate is pressed.
enum SummaryProvider: String, CaseIterable, Identifiable {
    case claude
    case onDevice

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .onDevice: "On device"
        }
    }
}

enum SummarySettings {
    static let providerKey = "summaryProvider"
    static let frameCountKey = "summaryFrameCount"
    /// What the settings stepper allows.
    static let frameCountRange = 1...12

    /// The build setting `RoamorySummaryFrames` (6 when it is missing or invalid): what Evaluate sends until settings change it.
    static var defaultFrameCount: Int {
        let value = (Bundle.main.infoDictionary?["RoamorySummaryFrames"] as? String).flatMap { Int($0) } ?? 6
        return min(max(value, frameCountRange.lowerBound), frameCountRange.upperBound)
    }

    /// How many frames Evaluate sends: the number set in settings, else `defaultFrameCount`.
    static var frameCount: Int {
        let saved = UserDefaults.standard.object(forKey: frameCountKey) as? Int
        return min(max(saved ?? defaultFrameCount, frameCountRange.lowerBound), frameCountRange.upperBound)
    }

    static var provider: SummaryProvider {
        UserDefaults.standard.string(forKey: providerKey).flatMap(SummaryProvider.init) ?? .claude
    }

    /// Whether the chosen model can run now: Claude needs a saved API key, the on-device model needs Apple Intelligence.
    static var isReady: Bool {
        switch provider {
        case .claude: APIKeyStore.load() != nil
        case .onDevice: OnDeviceSummarizer.unavailableReason == nil
        }
    }
}
