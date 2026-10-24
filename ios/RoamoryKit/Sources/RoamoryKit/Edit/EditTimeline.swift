import Foundation

/// Where each clip lands in the finished video (contracts README, "Duration").
/// Keep in step with `clip_output_s` and `total_duration_s` in backend/app/plan/validate.py.
public enum EditTimeline {
    public struct Slot: Sendable, Equatable {
        public var momentId: String
        public var startS: Double
        public var endS: Double
    }

    /// Output seconds for one clip. A ramp plays its first `over_s` source seconds in 4 equal steps.
    public static func outputLengthS(_ clip: EditSpec.Clip) -> Double {
        let length = clip.sourceLengthS
        guard let ramp = clip.speedRamp else { return length }
        return length - ramp.overS + ramp.stepRates.reduce(0) { $0 + (ramp.overS / 4) / $1 }
    }

    /// Overlap with the previous clip. The first clip's fade starts from black and overlaps nothing.
    public static func overlapS(_ clips: [EditSpec.Clip], at index: Int) -> Double {
        guard index > 0, clips[index].transitionIn != .cut else { return 0 }
        return clips[index].transitionS
    }

    public static func slots(_ spec: EditSpec) -> [Slot] {
        var slots: [Slot] = []
        var end = 0.0
        for (i, clip) in spec.clips.enumerated() {
            let start = end - overlapS(spec.clips, at: i)
            end = start + outputLengthS(clip)
            slots.append(Slot(momentId: clip.momentId, startS: start, endS: end))
        }
        return slots
    }

    /// Clip output lengths, minus transition overlaps, plus the end card. The title adds nothing.
    public static func totalDurationS(_ spec: EditSpec) -> Double {
        (slots(spec).last?.endS ?? 0) + spec.endCard.durationS
    }
}
