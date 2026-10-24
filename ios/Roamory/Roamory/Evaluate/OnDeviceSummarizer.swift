//
//  OnDeviceSummarizer.swift
//  Roamory
//

import Foundation
import FoundationModels
import ImageIO

/// Describes frames from the buffer with the iOS 27 on-device model (Foundation Models). Nothing leaves the iPhone.
/// The app runs on iOS 26, where this reports itself unavailable.
enum OnDeviceSummarizer {
    /// Longest side of a frame handed to the model. Smaller frames keep six of them inside its context window.
    private static let maxPixelSize = 768

    /// Why the model cannot be used now, or nil when it can.
    static var unavailableReason: String? {
        // Image input arrived in iOS 27; the iOS 26 model only takes text.
        guard #available(iOS 27, *) else {
            return "The on-device model needs iOS 27 to read images."
        }
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.capabilities.contains(.vision) ? nil : "The on-device model on this iPhone cannot read images."
        case .unavailable(.deviceNotEligible):
            return "This iPhone does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading."
        case .unavailable:
            return "The on-device model is unavailable."
        }
    }

    static func summarize(frames: [Data]) async throws -> String {
        guard #available(iOS 27, *), unavailableReason == nil else {
            throw SummaryClient.Failure(errorDescription: unavailableReason ?? "The on-device model is unavailable.")
        }
        let images = frames.compactMap(image)
        guard !images.isEmpty else {
            throw SummaryClient.Failure(errorDescription: "The frames could not be read.")
        }

        // The small model gives instructions more weight than the prompt and the end of the prompt more than the start,
        // so the traveler's details go into the instructions and the task is repeated after the frames.
        var instructions = SummaryClient.system
        let details = TripSettings.details()
        if let details {
            instructions += "\nBackground about this trip, given by the traveler. Treat it as true and use it to say who and what you see: \(details)"
        }
        let session = LanguageModelSession(model: .default, instructions: instructions)
        let prompt = Prompt {
            for (k, image) in images.enumerated() {
                "Frame \(k):"
                Attachment(image)
            }
            details == nil
                ? "Describe what is happening in these frames in 2 to 3 sentences."
                : "Describe what is happening in these frames in 2 to 3 sentences, using the background about this trip."
        }
        let text: String
        do {
            text = try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: 400)).content
        } catch LanguageModelError.contextSizeExceeded {
            throw SummaryClient.Failure(errorDescription: "The frames are too large for the on-device model.")
        }
        guard !text.isEmpty else {
            throw SummaryClient.Failure(errorDescription: "The on-device model gave no description.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes a JPEG, scaled down and turned upright.
    private static func image(_ jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
