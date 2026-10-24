//
//  OnDeviceSummarizer.swift
//  Roamory
//

import Foundation
import FoundationModels
import ImageIO

/// Describes frames from the buffer with the iOS 27 on-device model (Foundation Models). Nothing leaves the iPhone.
enum OnDeviceSummarizer {
    /// Longest side of a frame handed to the model. Smaller frames keep six of them inside its context window.
    private static let maxPixelSize = 768

    /// Why the model cannot be used now, or nil when it can.
    static var unavailableReason: String? {
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
        if let reason = unavailableReason {
            throw SummaryClient.Failure(errorDescription: reason)
        }
        let images = frames.compactMap(image)
        guard !images.isEmpty else {
            throw SummaryClient.Failure(errorDescription: "The frames could not be read.")
        }

        let session = LanguageModelSession(model: .default, instructions: SummaryClient.system)
        let prompt = Prompt {
            for (k, image) in images.enumerated() {
                "Frame \(k):"
                Attachment(image)
            }
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
