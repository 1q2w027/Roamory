import Foundation

/// Greedy planner used when the cloud plan is off, unreachable or invalid (TRD 9.1 step 3).
/// Deterministic: the same request gives the same spec whatever the clip order. Its output passes
/// `EditSpecValidator` whenever there is enough footage to reach the target; with too little it is
/// only too short (`EditSpecValidator.onlyTooShort`).
public enum FallbackPlanner {
    static let eps = 1e-6

    public static func plan(_ request: PlanRequest, preset: StylePreset, endCardText: String) -> EditSpec {
        let target = request.effectiveTargetS
        let high = EditSpecValidator.durationBounds(target).high
        let overlap = preset.transition == .cut ? 0 : preset.transitionS.default
        let clipS = preset.clipS

        func total(_ lengths: [Double]) -> Double {
            lengths.isEmpty ? 0 : lengths.reduce(0, +) - Double(lengths.count - 1) * overlap + preset.endCardS
        }

        // 1. Button moments first, then the rest by score.
        let ranked = request.clips.sorted(by: rankedBefore)
        let buttons = ranked.filter { $0.source == .button }
        var chosen = buttons
        var lengths: [Double]

        // 3. Button clips at the default length, cut toward clip_s.min when they don't all fit.
        if buttons.isEmpty {
            lengths = []
        } else {
            let n = Double(buttons.count)
            let fit = (target - preset.endCardS + (n - 1) * overlap) / n
            let length = min(max(fit, clipS.min), clipS.default)
            lengths = buttons.map { min(length, $0.durationS) }
        }

        // 2. Fill with the best other clips at the default length; shorten the last one to land on the target.
        for clip in ranked where clip.source != .button && clip.durationS >= clipS.min - eps {
            if total(lengths) >= target - eps { break }
            var length = min(clipS.default, clip.durationS)
            let over = total(lengths + [length]) - high
            if over > eps {
                length -= total(lengths + [length]) - target
                if length < clipS.min - eps { continue }
            }
            chosen.append(clip)
            lengths.append(length)
        }

        // Out of clips and still short: lengthen every clip evenly toward clip_s.max.
        var deficit = target - total(lengths)
        while deficit > eps {
            let caps = chosen.map { min(clipS.max, $0.durationS) }
            let growable = lengths.indices.filter { lengths[$0] < caps[$0] - eps }
            if growable.isEmpty { break }
            let share = deficit / Double(growable.count)
            for i in growable {
                let grow = min(share, caps[i] - lengths[i])
                lengths[i] += grow
                deficit -= grow
            }
        }

        // 4. Chronological order. 5. Preset defaults for transitions, captions and music.
        let order = chosen.indices.sorted { a, b in
            (chosen[a].tFromMs, chosen[a].momentId) < (chosen[b].tFromMs, chosen[b].momentId)
        }
        let clips = order.map { i in
            let clip = chosen[i]
            let (inS, outS) = trim(clip, length: lengths[i])
            return EditSpec.Clip(
                momentId: clip.momentId, inS: inS, outS: outS, transitionIn: preset.transition, transitionS: overlap,
                speedRamp: nil, caption: preset.captions ? clip.description : nil
            )
        }

        return EditSpec(
            tripId: request.tripId, style: request.style, output: preset.output,
            title: EditSpec.Title(text: titleText(request), subtitle: monthYear(request.startDate), durationS: preset.titleS),
            clips: clips,
            music: EditSpec.Music(track: preset.musicTrack, gainDb: preset.musicGainDb, duckOriginalAudio: !preset.keepOriginalAudio),
            endCard: EditSpec.EndCard(text: String(endCardText.prefix(40)), durationS: preset.endCardS)
        )
    }

    /// Higher score first (no score last), then earlier, then by id, so ties are deterministic.
    static func rankedBefore(_ a: PlanRequest.Clip, _ b: PlanRequest.Clip) -> Bool {
        let sa = a.score ?? -1, sb = b.score ?? -1
        if sa != sb { return sa > sb }
        return (a.tFromMs, a.momentId) < (b.tFromMs, b.momentId)
    }

    /// `length` seconds centered on the proposed window, kept inside the file, on whole milliseconds.
    static func trim(_ clip: PlanRequest.Clip, length: Double) -> (Double, Double) {
        let ms = { (s: Double) in (s * 1000).rounded() / 1000 }
        let length = ms(length)
        let center = (clip.proposedInS + clip.proposedOutS) / 2
        var inS = ms(min(max(center - length / 2, 0), max(clip.durationS - length, 0)))
        if inS + length > clip.durationS {
            inS = max(((clip.durationS - length) * 1000).rounded(.down) / 1000, 0)
        }
        return (inS, ms(inS + length))
    }

    static func titleText(_ request: PlanRequest) -> String {
        String((request.destination.city ?? request.destination.country).prefix(40))
    }

    static let months = ["January", "February", "March", "April", "May", "June", "July", "August",
                         "September", "October", "November", "December"]

    /// "2026-10-12" -> "October 2026", or nil if the date doesn't parse.
    static func monthYear(_ date: String) -> String? {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        return "\(months[month - 1]) \(year)"
    }
}
