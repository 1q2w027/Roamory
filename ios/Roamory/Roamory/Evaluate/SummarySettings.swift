//
//  SummarySettings.swift
//  Roamory
//

import Foundation
import FoundationModels
import Network

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
    static let offWiFiKey = "onDeviceWhenOffWiFi"

    /// The model picked in settings.
    static var provider: SummaryProvider {
        UserDefaults.standard.string(forKey: providerKey).flatMap(SummaryProvider.init) ?? .claude
    }

    /// Whether Claude gives way to the on-device model when the iPhone is not on Wi-Fi. On unless switched off.
    static var onDeviceWhenOffWiFi: Bool {
        UserDefaults.standard.object(forKey: offWiFiKey) as? Bool ?? true
    }

    /// The model Evaluate uses now: the one picked in settings, except that Claude is swapped for the on-device
    /// model when there is no Wi-Fi (and the on-device model can run).
    static func resolvedProvider() async -> SummaryProvider {
        guard provider == .claude, onDeviceWhenOffWiFi, OnDeviceSummarizer.unavailableReason == nil else { return provider }
        return await isOnWiFi() ? .claude : .onDevice
    }

    /// Whether Evaluate can run now: Claude needs a saved API key, the on-device model needs Apple Intelligence.
    static func isReady() async -> Bool {
        switch await resolvedProvider() {
        case .claude: APIKeyStore.load() != nil
        case .onDevice: OnDeviceSummarizer.unavailableReason == nil
        }
    }

    /// The first path a monitor reports is the current one.
    private static func isOnWiFi() async -> Bool {
        for await path in NWPathMonitor() {
            return path.status == .satisfied && path.usesInterfaceType(.wifi)
        }
        return false
    }
}
