//
//  SummaryClient.swift
//  Roamory
//

import Foundation

/// Describes frames from the buffer with the model chosen in settings: Claude through the Anthropic Messages API
/// (`AnthropicAPI`, the model is `RoamorySummaryModel` from the build settings) or the on-device model.
enum SummaryClient {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static let system = """
        You describe a short stretch of a traveler's trip from frames sampled evenly from it, oldest first.
        Reply with 2 to 3 plain sentences about what is happening and where it looks like, using only what is visible.
        Do not identify people (say "a person", "two friends") and do not name a place unless it is clearly recognizable.
        """

    /// What the traveler typed in the last onboarding step, worded as part of the prompt; nil when they skipped it.
    static var detailsPrompt: String? {
        TripSettings.details().map { "Details from the traveler about this trip (use them to understand what you see): \($0)" }
    }

    static func summarize(frames: [Data]) async throws -> String {
        switch SummarySettings.provider {
        case .claude: try await summarizeWithClaude(frames: frames)
        case .onDevice: try await OnDeviceSummarizer.summarize(frames: frames)
        }
    }

    private static func summarizeWithClaude(frames: [Data]) async throws -> String {
        var content: [[String: Any]] = []
        if let detailsPrompt { content.append(["type": "text", "text": detailsPrompt]) }
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
