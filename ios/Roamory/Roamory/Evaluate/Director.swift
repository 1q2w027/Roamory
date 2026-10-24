//
//  Director.swift
//  Roamory
//

import Foundation
import RoamoryKit

/// Decides, while the trip is filmed, what is worth saving. Every `interval` seconds the newest frames go to Claude
/// with what has been saved so far; it answers `save` or `skip`, and `CameraService` starts or stops saving the buffer.
enum Director {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    struct Decision: Decodable {
        enum Action: String, Decodable { case save, skip }
        let action: Action
        /// One sentence about what the frames show. It is how the director remembers what a saved clip holds.
        let summary: String
        let why: String
    }

    /// What the director is told besides the frames.
    struct State {
        var isSaving: Bool
        /// Length of the clip being saved, counting the footage that was in the buffer when it started.
        var savingSeconds: TimeInterval
        /// What the windows of the clip being saved showed, oldest first.
        var clipSoFar: [String]
        /// One summary per clip already saved this trip.
        var clips: [String]
    }

    /// A request ready to send, and what the debug log shows of it.
    struct Request {
        let body: [String: Any]
        let system: String
        /// The text around the frames; the frames themselves are `frames`.
        let prompt: String
    }

    /// Seconds between requests (build setting `RoamoryDirectorInterval`).
    static var interval: TimeInterval { setting("RoamoryDirectorInterval", fallback: 10, range: 2...120) }
    /// Frames in each request (build setting `RoamoryDirectorFrames`).
    static var frameCount: Int { Int(setting("RoamoryDirectorFrames", fallback: 5, range: 1...12)) }

    private static func setting(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        let value = (Bundle.main.infoDictionary?[key] as? String).flatMap(Double.init) ?? fallback
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "action": ["type": "string", "enum": ["save", "skip"]],
            "summary": ["type": "string"],
            "why": ["type": "string"],
        ],
        "required": ["action", "summary", "why"],
        "additionalProperties": false,
    ]

    private static let rules = """
        You are the director of a trip film. A traveler films their whole trip with a phone camera, and you decide \
        in real time which footage is kept for the highlight video. The camera always holds the last 45 seconds.

        Every few seconds you get a few frames from the camera, oldest first, spread over the time since your last \
        answer, and you answer with one decision:
        - "save": this footage belongs in the film. If nothing is being saved, the saved clip starts with the \
        footage the camera already holds, up to the last 45 seconds (less right after another clip ended), so answer \
        "save" as soon as the beginning of something good is visible; do not wait for it to finish. If a clip is \
        already being saved, "save" keeps it going.
        - "skip": not worth keeping. If a clip is being saved, "skip" ends it.

        Save footage with a clear subject or moment: a landmark, striking scenery, a meal, an activity, a show, \
        a lively street, the traveler's companions enjoying themselves, or arriving somewhere new. Prefer what \
        fits this trip's type, its style and what the traveler said about it.
        Skip transit and waiting (unless the view is beautiful), screens and menus, hotel rooms, corridors, \
        dark or blurry or covered frames, the floor or the ceiling, and views that repeat what an already saved clip \
        shows. Do not save a second clip of the same place or subject unless something clearly different happens.
        While a clip is being saved and the same subject or moment goes on, keep saving; judge repeats against the \
        clips already saved, not against the clip in progress. A good moment can have a dull second in it. End a clip \
        when the moment is clearly over, or when it has run long (about a minute) and stops showing anything new.

        Describe only what is visible. Never identify people; say "a person" or "two friends". Name a place only \
        if it is clearly recognizable or the traveler said so.

        Answer with JSON:
        - action: "save" or "skip".
        - summary: one plain sentence, at most 25 words, saying what these frames show. It is kept to remember \
        what is in each saved clip.
        - why: at most 15 words, the reason for your action.
        """

    /// The rules and the trip, the same for the whole trip, so Anthropic can cache it between requests.
    static func system() -> String {
        let defaults = UserDefaults.standard
        func text(_ key: String) -> String? {
            let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.flatMap { $0.isEmpty ? nil : $0 }
        }
        var trip = ["The film's style: \(TripSettings.style().rawValue)."]
        if let type = text(TripSettings.Key.tripType) { trip.append("Trip type: \(type).") }
        let place = [text(TripSettings.Key.city), text(TripSettings.Key.country)].compactMap { $0 }.joined(separator: ", ")
        if !place.isEmpty { trip.append("Destination: \(place).") }
        if let details = TripSettings.details() { trip.append("The traveler says: \(details)") }
        return rules + "\n\nThis trip:\n" + trip.joined(separator: "\n")
    }

    /// The text before the frames: what is saved already and what is happening now.
    static func context(_ state: State) -> String {
        var lines: [String] = []
        if state.clips.isEmpty {
            lines.append("No clips saved yet.")
        } else {
            lines.append("Clips already saved from this trip (\(state.clips.count)):")
            lines += state.clips.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }
        if state.isSaving {
            lines.append("Right now a clip is being saved. It is \(Int(state.savingSeconds)) s long so far"
                         + (state.clipSoFar.isEmpty ? "." : " and showed: " + condense(state.clipSoFar)))
        } else {
            lines.append("Right now nothing is being saved.")
        }
        return lines.joined(separator: "\n")
    }

    /// A clip's windows as one line. A long clip keeps its first window and its last two, so the request stays short.
    static func condense(_ windows: [String]) -> String {
        guard windows.count > 4 else { return windows.joined(separator: " Then: ") }
        return ([windows[0], "(\(windows.count - 3) more windows)"] + windows.suffix(2)).joined(separator: " Then: ")
    }

    static func request(frames: [Data], state: State) -> Request {
        let system = system()
        let before = context(state) + "\n\nThe newest \(frames.count) frames from the camera, oldest first:"
        let after = "Decide for these frames now."
        var content: [[String: Any]] = [["type": "text", "text": before]]
        for (k, jpeg) in frames.enumerated() {
            content.append(["type": "text", "text": "Frame \(k + 1):"])
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": after])
        let body: [String: Any] = [
            "model": AnthropicAPI.model("RoamoryDirectorModel"),
            // Thinking counts toward this, so it leaves room for the thinking before the short JSON answer.
            "max_tokens": 1024,
            // The cache covers everything up to here; the saved clips and the frames come after it.
            "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": content]],
        ]
        return Request(body: body, system: system, prompt: before + "\n[\(frames.count) frames]\n" + after)
    }

    static func parse(_ reply: AnthropicAPI.Reply) throws -> Decision {
        guard reply.stopReason != "max_tokens" else {
            throw Failure(errorDescription: "The director's answer was cut off before it finished.")
        }
        do {
            return try JSONDecoder().decode(Decision.self, from: Data(reply.text.utf8))
        } catch {
            throw Failure(errorDescription: "The director's answer was not a decision: \(reply.text.prefix(200))")
        }
    }
}
