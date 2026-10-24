import Foundation

/// Plans an edit on the phone with no model: evenly spaced cuts from the trip's clips, in recording order, at the
/// style preset's clip length, transition, title and music. The backup when Roamory Studio is not available.
public enum LocalPlanner {
    public struct Clip: Sendable, Equatable {
        public var id: String
        public var durationS: Double

        public init(id: String, durationS: Double) {
            self.id = id
            self.durationS = durationS
        }
    }

    /// - Parameter clips: in recording order. Clips too short for the style's transitions are skipped,
    ///   so the spec has no clips when none is long enough.
    public static func plan(
        tripId: String, style: Style, preset: StylePreset, clips: [Clip], title: String, subtitle: String?, endCardText: String
    ) -> EditSpec {
        let overlap = preset.transition == .cut ? 0 : preset.transitionS.default
        // A cut must outlast the overlaps at both of its ends.
        let usable = clips.filter { $0.durationS > 2 * overlap + 0.5 }
        let lengths = usable.map { ms(min(preset.clipS.default, $0.durationS)) }
        let footageS = preset.targetS.default - preset.endCardS - overlap
        let wanted = max(1, Int((footageS / (preset.clipS.default - overlap)).rounded()))
        let counts = allocate(wanted, durations: usable.map(\.durationS), lengths: lengths)

        var cuts: [EditSpec.Clip] = []
        for (i, clip) in usable.enumerated() where counts[i] > 0 {
            let length = lengths[i]
            for j in 0..<counts[i] {
                let center = clip.durationS * (Double(j) + 0.5) / Double(counts[i])
                let inS = floorMs(min(max(center - length / 2, 0), clip.durationS - length))
                cuts.append(EditSpec.Clip(
                    momentId: clip.id, inS: inS, outS: ms(inS + length), transitionIn: preset.transition, transitionS: overlap,
                    speedRamp: nil, caption: nil
                ))
            }
        }

        return EditSpec(
            tripId: tripId, style: style, output: preset.output,
            title: EditSpec.Title(text: String(title.prefix(40)), subtitle: subtitle, durationS: preset.titleS),
            clips: cuts,
            music: EditSpec.Music(track: preset.musicTrack, gainDb: preset.musicGainDb, duckOriginalAudio: !preset.keepOriginalAudio),
            endCard: EditSpec.EndCard(text: String(endCardText.prefix(40)), durationS: preset.endCardS)
        )
    }

    /// How many cuts to take from each clip. Fewer wanted than clips: one each from evenly spaced clips.
    /// Otherwise one each, then the rest to whichever clip has the most footage per cut, up to what fits.
    static func allocate(_ wanted: Int, durations: [Double], lengths: [Double]) -> [Int] {
        let n = durations.count
        guard n > 0 else { return [] }
        if wanted <= n {
            var counts = Array(repeating: 0, count: n)
            for k in 0..<wanted { counts[Int((Double(k) + 0.5) * Double(n) / Double(wanted))] = 1 }
            return counts
        }
        let capacity = durations.indices.map { max(1, Int(durations[$0] / lengths[$0])) }
        var counts = Array(repeating: 1, count: n)
        for _ in n..<wanted {
            let open = counts.indices.filter { counts[$0] < capacity[$0] }
            guard let best = open.max(by: { durations[$0] / Double(counts[$0] + 1) < durations[$1] / Double(counts[$1] + 1) }) else { break }
            counts[best] += 1
        }
        return counts
    }

    private static func ms(_ s: Double) -> Double { (s * 1000).rounded() / 1000 }
    private static func floorMs(_ s: Double) -> Double { max((s * 1000).rounded(.down) / 1000, 0) }
}
