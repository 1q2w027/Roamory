import RoamoryKit
import SwiftUI

/// Trip context and consent for moment detection, until onboarding exists (PRD §4). Stored per device.
struct DetectionSettings {
    enum Key {
        static let cloudAllowed = "detection.cloudAllowed"
        static let style = "detection.style"
        static let tripType = "detection.tripType"
        static let country = "detection.country"
        static let city = "detection.city"
        static let demoMode = "detection.demoMode"
        static let installId = "detection.installId"
    }

    var cloudAllowed = true
    var style = Style.cinematic
    var tripType = "honeymoon"
    var country = "Japan"
    var city = "Kyoto"
    var demoMode = false

    static func current(_ defaults: UserDefaults = .standard) -> DetectionSettings {
        var s = DetectionSettings()
        if defaults.object(forKey: Key.cloudAllowed) != nil { s.cloudAllowed = defaults.bool(forKey: Key.cloudAllowed) }
        if let raw = defaults.string(forKey: Key.style), let style = Style(rawValue: raw) { s.style = style }
        if let v = defaults.string(forKey: Key.tripType), !v.isEmpty { s.tripType = v }
        if let v = defaults.string(forKey: Key.country), !v.isEmpty { s.country = v }
        s.city = defaults.string(forKey: Key.city) ?? s.city
        s.demoMode = defaults.bool(forKey: Key.demoMode)
        return s
    }

    /// A random id made once per install (TRD §8.1); not a device identifier.
    static func installId(_ defaults: UserDefaults = .standard) -> String {
        if let id = defaults.string(forKey: Key.installId) { return id }
        let id = "i_\(UUID().uuidString.prefix(8).lowercased())"
        defaults.set(id, forKey: Key.installId)
        return id
    }
}

struct DetectionSettingsView: View {
    @AppStorage(DetectionSettings.Key.cloudAllowed) private var cloudAllowed = true
    @AppStorage(DetectionSettings.Key.style) private var style = Style.cinematic.rawValue
    @AppStorage(DetectionSettings.Key.tripType) private var tripType = "honeymoon"
    @AppStorage(DetectionSettings.Key.country) private var country = "Japan"
    @AppStorage(DetectionSettings.Key.city) private var city = "Kyoto"
    @AppStorage(DetectionSettings.Key.demoMode) private var demoMode = false
    @Environment(\.dismiss) private var dismiss
    let backend: String?

    var body: some View {
        Form {
            Section {
                Toggle("Allow cloud analysis", isOn: $cloudAllowed)
                LabeledContent("Backend", value: backend ?? "Not set")
            } footer: {
                Text(backend == nil
                     ? "Set ROAMORY_API_BASE_URL and ROAMORY_APP_TOKEN in ios/Roamory/Config/Local.xcconfig, then rebuild. Until then only the on-phone fallback and the button keep moments."
                     : "Small still frames go to the backend; full video never leaves the phone.")
            }
            Section {
                Picker("Style", selection: $style) {
                    ForEach(Style.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                }
                TextField("Trip type", text: $tripType)
                TextField("Country", text: $country)
                TextField("City", text: $city)
            } header: {
                Text("Trip")
            } footer: {
                Text("Reels records 9:16 (hold the phone upright); the other styles record 16:9 (turn it sideways). The video format applies the next time the camera starts.")
            }
            Section {
                Toggle("Demo mode", isOn: $demoMode)
            } footer: {
                Text("Shorter cooldown and a lower threshold, for the demo walk (TRD §8.3). Applies to the next recording.")
            }
        }
        .navigationTitle("Moment detection")
        .toolbar { Button("Done") { dismiss() } }
    }
}
