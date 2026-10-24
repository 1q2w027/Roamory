//
//  AnthropicAPI.swift
//  Roamory
//

import Foundation

/// One request to the Anthropic Messages API, shared by Evaluate and Ask. The API key comes from the Keychain
/// (`APIKeyStore`); each caller names its model from the build settings.
enum AnthropicAPI {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// The model in Info.plist under `key`, or `fallback` when it is missing.
    static func model(_ key: String, fallback: String = "claude-haiku-5-5") -> String {
        Bundle.main.infoDictionary?[key] as? String ?? fallback
    }

    /// Sends `body` (model, max_tokens, system, messages, …) and returns the reply's text.
    static func send(_ body: [String: Any], timeout: TimeInterval = 30) async throws -> String {
        guard let key = APIKeyStore.load() else {
            throw Failure(errorDescription: "No API key saved.")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw Failure(errorDescription: message ?? "Anthropic returned an unexpected response.")
        }
        let text = (json?["content"] as? [[String: Any]])?
            .first { $0["type"] as? String == "text" }?["text"] as? String
        guard json?["stop_reason"] as? String != "refusal", let text, !text.isEmpty else {
            throw Failure(errorDescription: "Claude gave no answer.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
