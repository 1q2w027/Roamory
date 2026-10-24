import CoreMotion
import Foundation

/// How still the wearer is, 0...1, from Core Motion activity (TRD §6 `dwell`): 1 stationary, 0 walking or
/// running, 0.5 otherwise. 0 when motion data is unavailable or not allowed.
nonisolated final class MotionDwell: @unchecked Sendable {
    private let manager = CMMotionActivityManager()
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var value = 0.0

    var current: Double { lock.withLock { value } }

    func start() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        manager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let self, let activity else { return }
            let dwell = activity.stationary ? 1 : (activity.walking || activity.running || activity.cycling) ? 0 : 0.5
            self.lock.withLock { self.value = dwell }
        }
    }

    func stop() {
        manager.stopActivityUpdates()
        lock.withLock { value = 0 }
    }
}
