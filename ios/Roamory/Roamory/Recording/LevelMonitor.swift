//
//  LevelMonitor.swift
//  Roamory
//

import Combine
import CoreMotion
import RoamoryKit
import SwiftUI

/// Reads the phone's motion while the mount level shows and plays its haptics; the logic is `LevelGuide`.
@MainActor
final class LevelMonitor: ObservableObject {
    @Published private(set) var pose: LevelPose?
    @Published private(set) var isLevel = false

    private let motion = CMMotionManager()
    private let haptics = LevelHaptics()
    private let config = try? LevelConfig.bundled()
    private var guide: LevelGuide?

    /// False without a motion sensor (or the bundled config): then there is no level at all.
    var isAvailable: Bool { config != nil && motion.isDeviceMotionAvailable }
    /// How long the level stays on screen once the phone is level.
    var fadeDelay: TimeInterval { config?.fadeDelayS ?? 1 }
    var bubbleRangeDeg: Double { config?.bubbleRangeDeg ?? 10 }
    var toleranceDeg: Double { config?.toleranceDeg ?? 4 }
    var aimToleranceDeg: Double { config?.aimToleranceDeg ?? 7 }

    /// `captureAngle` is the rotation the session records at (`CameraService.captureRotationAngle`).
    func start(captureAngle: Double) {
        guard let config, isAvailable, guide == nil else { return }
        guide = LevelGuide(captureAngle: captureAngle, config: config)
        haptics.start()
        motion.deviceMotionUpdateInterval = 1 / config.updateHz
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let self, let sample, var guide = self.guide else { return }
            let g = sample.gravity, r = sample.rotationRate
            let haptic = guide.update(gravity: SIMD3(g.x, g.y, g.z), rotationRate: SIMD3(r.x, r.y, r.z),
                                      at: sample.timestamp)
            self.guide = guide
            self.pose = guide.pose
            if self.isLevel != guide.isLevel { self.isLevel = guide.isLevel }
            if let haptic { self.haptics.play(haptic) }
        }
    }

    func stop() {
        guard guide != nil else { return }
        motion.stopDeviceMotionUpdates()
        haptics.stop()
        guide = nil
        pose = nil
        isLevel = false
    }
}
