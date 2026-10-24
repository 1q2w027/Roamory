//
//  SummaryClient.swift
//  Roamory
//

import Foundation

/// Sends frames from the buffer to the Anthropic Messages API and returns Claude's description of them.
/// The model is `RoamorySummaryModel` from the build settings.
enum SummaryClient {
    private static let system = """
        You describe a short stretch of a traveler's trip from frames sampled evenly from it, oldest first.
        Reply with 2 to 3 plain sentences about what is happening and where it looks like, using only what is visible.
        Do not identify people (say "a person", "two friends") and do not name a place unless it is clearly recognizable.
        """

    static func summarize(frames: [Data]) async throws -> String {
        var content: [[String: Any]] = []
        for (k, jpeg) in frames.enumerated() {
            content.append(["type": "text", "text": "Frame \(k):"])
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        return try await AnthropicAPI.send([
            "model": AnthropicAPI.model("RoamorySummaryModel"),
            "max_tokens": 400,
            "system": system,
            "messages": [["role": "user", "content": content]],
        ])
    }
}
