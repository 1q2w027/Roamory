import Foundation

/// How a replayed walk did against its labeled moments (TRD 12.1 gate 6).
public struct ReplayReport: Sendable, Equatable {
    public struct MomentResult: Sendable, Equatable {
        public var labelMs: Int
        /// An escalation lies within the tolerance of the label.
        public var escalated: Bool
        /// A kept moment lies within the tolerance of the label.
        public var kept: Bool
    }

    public var samples: Int
    public var escalations: Int
    /// Escalations per sample; gate 6 wants at most 0.10.
    public var escalationRate: Double
    public var moments: [MomentResult]

    public static func compute(samples: Int, escalatedMs: [Int], keptMs: [Int], labelsMs: [Int], toleranceMs: Int) -> ReplayReport {
        func near(_ t: Int, _ times: [Int]) -> Bool { times.contains { abs($0 - t) <= toleranceMs } }
        return ReplayReport(
            samples: samples, escalations: escalatedMs.count,
            escalationRate: samples > 0 ? Double(escalatedMs.count) / Double(samples) : 0,
            moments: labelsMs.map { MomentResult(labelMs: $0, escalated: near($0, escalatedMs), kept: near($0, keptMs)) }
        )
    }
}
