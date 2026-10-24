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
