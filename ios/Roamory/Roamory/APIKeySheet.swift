//
//  APIKeySheet.swift
//  Roamory
//

import SwiftUI

/// Asks for the Anthropic API key and saves it to the Keychain.
struct APIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = APIKeyStore.load() != nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(hasKey ? "Replace the saved key" : "sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    Text("Kept in this iPhone's Keychain, not in the app. Evaluate sends frames from the buffer to Anthropic with it.")
                }
                if hasKey {
                    Button("Remove saved key", role: .destructive) {
                        APIKeyStore.delete()
                        hasKey = false
                    }
                }
            }
            .navigationTitle("API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        APIKeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
