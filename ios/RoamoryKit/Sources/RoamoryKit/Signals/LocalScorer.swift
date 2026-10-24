import Foundation

/// Local score L and its parts for one sample (TRD 6).
public struct LocalScore: Sendable, Equatable {
    public var l: Double
    public var changeSpike: Double
    public var quality: Double
    public var novelty: Double
}

/// L = w·changeSpike + w·dwell + w·quality + w·novelty, with weights and scales from `DetectionConfig`.
public struct LocalScorer: Sendable {
    let config: DetectionConfig
    /// Recent `change` values, the baseline a spike is measured against.
    private var changes: [Double] = []

    public init(config: DetectionConfig) {
        self.config = config
    }

    /// - Parameter dwell: 0…1 from motion sensors; 1 when the wearer has stopped.
    /// - Parameter recentEscalated: dHashes of recently escalated samples.
    public mutating func score(_ s: FrameSignals, dwell: Double, recentEscalated: [UInt64]) -> LocalScore {
        let baseline = changes.isEmpty ? 0 : changes.reduce(0, +) / Double(changes.count)
        let changeSpike = clamp((s.change - baseline) / config.changeSpikeScale)
        changes.append(s.change)
        if changes.count > config.changeWindow { changes.removeFirst(changes.count - config.changeWindow) }

        let quality = clamp(s.sharpness / config.sharpnessFull) * (1 - clamp(s.clippedFraction))
        let novelty = recentEscalated.map { hammingDistance($0, s.dhash) }.min()
            .map { clamp(Double($0) / Double(config.noveltyFullBits)) } ?? 1

        // An unusable frame never becomes a candidate, even as a change spike while the wearer stands still.
        let l = quality < config.minQuality ? 0
            : config.weightChangeSpike * changeSpike + config.weightDwell * clamp(dwell)
                + config.weightQuality * quality + config.weightNovelty * novelty
        return LocalScore(l: l, changeSpike: changeSpike, quality: quality, novelty: novelty)
    }

    /// Forget the change baseline, e.g. at the start of a new recording session.
    public mutating func reset() {
        changes.removeAll()
    }
}

/// Clamps to 0…1, mapping NaN to 0.
func clamp(_ x: Double) -> Double {
    x.isNaN ? 0 : min(max(x, 0), 1)
}
