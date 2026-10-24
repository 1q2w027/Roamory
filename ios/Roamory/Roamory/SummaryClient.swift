//
//  SummaryClient.swift
//  Roamory
//

import Foundation

/// Sends frames from the buffer to the Anthropic Messages API and returns Claude's description of them.
/// The API key comes from the Keychain (`APIKeyStore`), the model from the build settings.
enum SummaryClient {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private static let system = """
        You describe a short stretch of a traveler's trip from frames sampled evenly from it, oldest first.
        Reply with 2 to 3 plain sentences about what is happening and where it looks like, using only what is visible.
        Do not identify people (say "a person", "two friends") and do not name a place unless it is clearly recognizable.
        """

    static func summarize(frames: [Data]) async throws -> String {
        guard let key = APIKeyStore.load() else {
            throw Failure(errorDescription: "No API key saved.")
        }
        let model = Bundle.main.infoDictionary?["RoamorySummaryModel"] as? String ?? "claude-haiku-5-5"

        var content: [[String: Any]] = []
        for (k, jpeg) in frames.enumerated() {
            content.append(["type": "text", "text": "Frame \(k):"])
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 400,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 30)
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
            throw Failure(errorDescription: "Claude gave no description.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
