import Foundation

/// Button moments win over the length target (PRD FR-009, contracts README "Effective target").
public enum EffectiveTarget {
    /// `max(preset.target_s.default, buttons x preset.clip_s.min + preset.end_card_s)`. The title is overlaid and adds nothing.
    public static func seconds(buttonCount: Int, preset: StylePreset) -> Double {
        max(preset.targetS.default, Double(buttonCount) * preset.clipS.min + preset.endCardS)
    }
}
