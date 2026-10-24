//
//  SettingsSheet.swift
//  Roamory
//

import FoundationModels
import SwiftUI

/// General settings: which model describes the buffer (Claude or the on-device model), and the Anthropic API key for Claude.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SummarySettings.providerKey) private var provider = SummaryProvider.claude
    @State private var key = ""
    @State private var hasKey = APIKeyStore.load() != nil

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Model", selection: $provider) {
                        ForEach(SummaryProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Evaluate")
                } footer: {
                    Text("Which model describes the frames from the buffer.")
                }
                switch provider {
                case .claude: claudeSection
                case .onDevice: onDeviceSection
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveKey()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var claudeSection: some View {
        Section {
            SecureField(hasKey ? "Replace the saved key" : "sk-ant-…", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(saveKey)
            if hasKey {
                Button("Remove saved key", role: .destructive) {
                    APIKeyStore.delete()
                    hasKey = false
                }
            }
        } header: {
            Text("Anthropic API key")
        } footer: {
            Text("Kept in this iPhone's Keychain, not in the app. Evaluate sends frames from the buffer to Anthropic with it.")
        }
    }

    @ViewBuilder
    private var onDeviceSection: some View {
        let reason = OnDeviceSummarizer.unavailableReason
        Section {
            if #available(iOS 27, *) {
                LabeledContent("Model", value: SystemLanguageModel.default.variant.displayName)
            }
            LabeledContent("Status") {
                if let reason {
                    Text(reason).foregroundStyle(.red).multilineTextAlignment(.trailing)
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        } header: {
            Text("On-device model")
        } footer: {
            Text("Apple's model on this iPhone describes the frames. They never leave the phone and no API key is needed.")
        }
    }

    private func saveKey() {
        guard !trimmedKey.isEmpty, APIKeyStore.save(trimmedKey) else { return }
        hasKey = true
        key = ""
    }
}
