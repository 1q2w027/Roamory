//
//  SettleGate.swift
//  Roamary
//

import Foundation

/// Decides which camera frames may enter the buffer. Right after the camera starts (or comes back from an
/// interruption) auto white balance and exposure are still converging and the picture is tinted, so those
/// frames are held back until the camera reports it has settled.
nonisolated struct SettleGate {
    /// Frames this soon after the camera starts are always held back; the adjusting flags may not have gone up yet.
    var minWait = 0.5
    /// Give up waiting for the camera to settle after this long.
    var maxWait = 3.0
    /// A pause in the frames longer than this means the camera restarted.
    var restartGap = 1.0

    private var firstTime: Double?
    private var lastTime: Double?
    private var isOpen = false

    /// Whether the frame at `time` (seconds) goes into the buffer. Once open, the gate stays open until the camera restarts.
    mutating func admit(at time: Double, isAdjusting: Bool) -> Bool {
        if let lastTime, time - lastTime > restartGap {
            isOpen = false
            firstTime = nil
        }
        lastTime = time
        if isOpen { return true }
        let first = firstTime ?? time
        firstTime = first
        let waited = time - first
        if waited >= minWait && (!isAdjusting || waited >= maxWait) { isOpen = true }
        return isOpen
    }
}
