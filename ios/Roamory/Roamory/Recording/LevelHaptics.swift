//
//  LevelHaptics.swift
//  Roamory
//

import AVFoundation
import CoreHaptics
import RoamoryKit
import UIKit

/// Plays the mount level's ticks, success double tap and warning. iOS mutes haptics while the audio session
/// records, so they are allowed only between `start()` and `stop()`.
@MainActor
final class LevelHaptics {
    private var engine: CHHapticEngine?
    /// The audio session calls can block, so they run off the main thread, in order.
    private let audioQueue = DispatchQueue(label: "roamory.level.audio")

    func start() {
        audioQueue.async { try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true) }
        guard engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine(audioSession: .sharedInstance()) else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        do {
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    func stop() {
        engine?.stop()
        engine = nil
        audioQueue.async { try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(false) }
    }

    func play(_ haptic: LevelHaptic) {
        let events: [CHHapticEvent]
        switch haptic {
        case .tick(let intensity):
            events = [Self.tap(at: 0, intensity: intensity, sharpness: 0.4 + 0.6 * intensity)]
        case .success:
            events = [Self.tap(at: 0, intensity: 1, sharpness: 1), Self.tap(at: 0.12, intensity: 1, sharpness: 1)]
        case .warning:
            events = [Self.tap(at: 0, intensity: 0.5, sharpness: 0.2)]
        }
        do {
            guard let engine else { throw CocoaError(.featureUnsupported) }
            try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])).start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallback(haptic)
        }
    }

    private func playFallback(_ haptic: LevelHaptic) {
        switch haptic {
        case .tick(let intensity): UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: intensity)
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private static func tap(at time: TimeInterval, intensity: Double, sharpness: Double) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness)),
        ], relativeTime: time)
    }
}
