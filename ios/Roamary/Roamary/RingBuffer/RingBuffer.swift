//
//  RingBuffer.swift
//  Roamary
//

import Foundation

/// The last `retention` seconds of samples, oldest first. It only looks at timestamps and keyframe flags,
/// so it works with any payload (encoded sample buffers in the app, plain values in tests).
nonisolated struct RingBuffer<Payload> {
    nonisolated struct Entry {
        /// Presentation time in seconds.
        var time: Double
        var isKeyframe: Bool
        var payload: Payload
    }

    var retention: Double
    private(set) var entries: [Entry] = []

    init(retention: Double) {
        self.retention = retention
    }

    var first: Entry? { entries.first }
    var last: Entry? { entries.last }
    var isEmpty: Bool { entries.isEmpty }

    /// Seconds between the oldest and newest entry.
    var duration: Double {
        guard let first, let last else { return 0 }
        return last.time - first.time
    }

    /// Adds a sample (times must not go backwards) and drops what has aged out.
    /// While the buffer is empty, samples before the first keyframe are ignored, so it always starts on one.
    mutating func append(_ entry: Entry) {
        if entries.isEmpty && !entry.isKeyframe { return }
        entries.append(entry)
        trim(before: entry.time - retention)
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    /// Drops entries older than `time`, but only back to the last keyframe at or before it,
    /// so the buffer always starts on a keyframe and its first entry can be decoded on its own.
    mutating func trim(before time: Double) {
        guard let index = keyframeIndex(atOrBefore: time), index > 0 else { return }
        entries.removeFirst(index)
    }

    /// Index of the last keyframe at or before `time`.
    func keyframeIndex(atOrBefore time: Double) -> Int? {
        entries.lastIndex { $0.time <= time && $0.isKeyframe }
    }

    /// Entries up to `end`, starting at the keyframe at or before `start` (or at the oldest entry when none is).
    func range(from start: Double, to end: Double = .infinity) -> [Entry] {
        let from = keyframeIndex(atOrBefore: start) ?? 0
        return entries[from...].prefix { $0.time <= end }.map { $0 }
    }
}
