import RoamoryKit
import SwiftUI

/// The trip details the edit uses for its style, titles and captions (PRD onboarding, trimmed to what editing needs).
struct TripSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = TripSettings.load()
    var onSave: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section("Video style") {
                    Picker("Style", selection: $settings.style) {
                        ForEach(Style.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Trip") {
                    Picker("Trip type", selection: $settings.tripType) {
                        ForEach(TripSettings.tripTypes, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Country", text: $settings.country)
                    TextField("City (optional)", text: $settings.city)
                    Stepper("\(settings.lengthDays) day\(settings.lengthDays == 1 ? "" : "s")",
                            value: $settings.lengthDays, in: 1...60)
                }
                Section {
                    Toggle("Allow cloud analysis", isOn: $settings.allowCloudAnalysis)
                } footer: {
                    Text("Sends small, low-resolution frames to Roamory's server to pick moments and plan the edit. "
                         + "Off, everything runs on the phone and only moments you mark are kept.")
                }
            }
            .navigationTitle("Trip setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settings.save()
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}
