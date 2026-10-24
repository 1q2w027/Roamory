import Foundation

/// A sample the gate decided to send to the cloud.
public struct Escalation: Sendable, Equatable {
    /// Trip-clock time of the escalated sample (one sample before the push that confirmed a peak).
    public var tMs: Int
    public var dhash: UInt64
    /// Raw local score L of that sample.
    public var l: Double
    public var forced: Bool

    public init(tMs: Int, dhash: UInt64, l: Double, forced: Bool) {
        self.tMs = tMs
        self.dhash = dhash
        self.l = l
        self.forced = forced
    }
}

/// Decides which samples become cloud candidates (TRD 6 rules 1-5) and keeps the phone's token bucket (TRD 8.3).
public struct EscalationGate: Sendable {
    private struct Sample {
        var tMs: Int
        var l: Double
        var dhash: UInt64
        var smoothed: Double
    }

    let config: DetectionConfig
    let cooldownMs: Int
    let tauBase: Double

    private var history: [Sample] = []  // the last 2 samples
    private var pushes = 0
    private var lastEscalatedMs: Int?
    private var lastEscalatedDhash: UInt64?
    private var bucket: Double
    private var refilledAtMs: Int?

    public init(config: DetectionConfig, demoMode: Bool = false) {
        self.config = config
        self.cooldownMs = Int((demoMode ? config.demoCooldownS : config.cooldownS) * 1000)
        self.tauBase = demoMode ? config.demoTauBase : config.tauBase
        self.bucket = config.bucketCapacity
    }

    /// Tokens left as of the last push.
    public var tokens: Double { bucket }

    public static func threshold(tokens: Double, capacity: Double, base: Double, slope: Double) -> Double {
        base + slope * (1 - tokens / capacity)
    }

    public mutating func push(tMs: Int, l: Double, dhash: UInt64, cloudAllowed: Bool) -> Escalation? {
        refill(to: tMs)
        pushes += 1
        let smoothed = config.smoothingAlpha * l + (1 - config.smoothingAlpha) * (history.last?.smoothed ?? 0)
        let current = Sample(tMs: tMs, l: l, dhash: dhash, smoothed: smoothed)
        defer { history = Array((history + [current]).suffix(2)) }

        // Rules 1-2: the previous sample is a smoothed local peak above the threshold.
        if let prev = history.last {
            let beforePrev = history.count == 2 ? history[0].smoothed : 0
            let tau = Self.threshold(tokens: bucket, capacity: config.bucketCapacity, base: tauBase, slope: config.tauBudgetSlope)
            if prev.smoothed >= tau, prev.smoothed >= beforePrev, prev.smoothed > current.smoothed,
               let e = escalateIfAllowed(prev, forced: false, cloudAllowed: cloudAllowed) {
                return e
            }
        }
        // A forced sample skips rules 1-2 but not 3-5.
        if pushes.isMultiple(of: config.forcedEvery) {
            return escalateIfAllowed(current, forced: true, cloudAllowed: cloudAllowed)
        }
        return nil
    }

    /// Clears smoothing and peak history for a new recording session; cooldown, last hash and bucket carry over.
    public mutating func reset() {
        history.removeAll()
    }

    /// Rules 3-5: cooldown, distinct from the last escalated frame, budget and consent.
    private mutating func escalateIfAllowed(_ s: Sample, forced: Bool, cloudAllowed: Bool) -> Escalation? {
        guard cloudAllowed, bucket >= 1 else { return nil }
        if let last = lastEscalatedMs, s.tMs - last < cooldownMs { return nil }
        if let hash = lastEscalatedDhash, hammingDistance(hash, s.dhash) < config.minDhashDistance { return nil }
        bucket -= 1
        lastEscalatedMs = s.tMs
        lastEscalatedDhash = s.dhash
        return Escalation(tMs: s.tMs, dhash: s.dhash, l: s.l, forced: forced)
    }

    private mutating func refill(to tMs: Int) {
        if let at = refilledAtMs, tMs > at {
            bucket = min(config.bucketCapacity, bucket + Double(tMs - at) / 1000 / config.bucketRefillS)
        }
        refilledAtMs = max(tMs, refilledAtMs ?? tMs)
    }
}
