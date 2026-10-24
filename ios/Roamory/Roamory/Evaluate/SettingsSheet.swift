//
//  SettingsSheet.swift
//  Roamory
//

import SwiftUI

/// General settings: the Anthropic API key that the director and Ask use.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = APIKeyStore.load() != nil

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
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
                    Text("Kept in this iPhone's Keychain, not in the app. Ask Roamy and the director, which picks what to save while you film, use it to talk to Anthropic.")
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

    private func saveKey() {
        guard !trimmedKey.isEmpty, APIKeyStore.save(trimmedKey) else { return }
        hasKey = true
        key = ""
    }
}
