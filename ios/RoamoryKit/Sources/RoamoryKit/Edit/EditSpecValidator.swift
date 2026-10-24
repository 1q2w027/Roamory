import Foundation

/// A broken edit-spec rule (contracts README, "Edit spec rules"). `index` is the position in `spec.clips`.
public enum EditSpecError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownMoment(index: Int, momentId: String)
    case duplicateMoment(index: Int, momentId: String)
    case trimOutOfBounds(index: Int, momentId: String, inS: Double, outS: Double, durationS: Double)
    case clipLengthOutOfRange(index: Int, momentId: String, lengthS: Double, min: Double, max: Double)
    case transitionMismatch(index: Int, momentId: String)
    case speedRampNotAllowed(index: Int, momentId: String)
    case speedRampOutsideLeadIn(index: Int, momentId: String, leadInS: Double)
    case speedRampTooLong(index: Int, momentId: String)
    case captionNotAllowed(index: Int, momentId: String)
    case captionNotInAllowedList(index: Int, momentId: String, caption: String)
    case missingButtonMoment(momentId: String)
    case durationOutOfRange(totalS: Double, lowS: Double, highS: Double)

    public var description: String {
        switch self {
        case let .unknownMoment(i, id): "clips[\(i)] (\(id)): moment_id is not in the request"
        case let .duplicateMoment(i, id): "clips[\(i)] (\(id)): moment_id appears more than once"
        case let .trimOutOfBounds(i, id, inS, outS, d): "clips[\(i)] (\(id)): need 0 <= in_s < out_s <= \(d), got in_s=\(inS) out_s=\(outS)"
        case let .clipLengthOutOfRange(i, id, l, lo, hi): "clips[\(i)] (\(id)): length \(l)s is outside clip_s [\(lo), \(hi)]"
        case let .transitionMismatch(i, id): "clips[\(i)] (\(id)): transition_s must be 0 exactly when transition_in is cut"
        case let .speedRampNotAllowed(i, id): "clips[\(i)] (\(id)): speed_ramp must be null for this style"
        case let .speedRampOutsideLeadIn(i, id, lead): "clips[\(i)] (\(id)): speed_ramp needs in_s + over_s <= low_fps_lead_in_s (\(lead))"
        case let .speedRampTooLong(i, id): "clips[\(i)] (\(id)): speed_ramp over_s must be <= out_s - in_s"
        case let .captionNotAllowed(i, id): "clips[\(i)] (\(id)): caption must be null for this style"
        case let .captionNotInAllowedList(i, id, c): "clips[\(i)] (\(id)): caption \"\(c)\" is not one of the allowed strings"
        case let .missingButtonMoment(id): "missing button moment \(id)"
        case let .durationOutOfRange(t, lo, hi): "total duration \(t)s is outside \(lo)-\(hi)s"
        }
    }
}

/// The phone's copy of the edit-spec rules. Keep in step with backend/app/plan/validate.py.
public enum EditSpecValidator {
    static let eps = 1e-6
    public static let durationTolerance = 0.10

    public static func allowedCaptions(_ request: PlanRequest) -> Set<String> {
        var allowed: Set<String> = [request.destination.country, request.tripType]
        if let city = request.destination.city {
            allowed.insert(city)
            allowed.insert("\(city), \(request.destination.country)")
        }
        allowed.formUnion(request.clips.compactMap(\.description))
        return allowed
    }

    /// Every broken rule, in spec order; empty means valid.
    public static func validate(_ spec: EditSpec, request: PlanRequest, preset: StylePreset) -> [EditSpecError] {
        var errors: [EditSpecError] = []
        let clipsById = Dictionary(request.clips.map { ($0.momentId, $0) }, uniquingKeysWith: { first, _ in first })
        let captions = allowedCaptions(request)
        var seen: Set<String> = []

        for (i, ec) in spec.clips.enumerated() {
            let id = ec.momentId
            // 1. id exists, no repeats
            guard let src = clipsById[id] else {
                errors.append(.unknownMoment(index: i, momentId: id))
                continue
            }
            if !seen.insert(id).inserted {
                errors.append(.duplicateMoment(index: i, momentId: id))
            }

            // 2. trims inside the clip file
            if !(0 <= ec.inS && ec.inS < ec.outS && ec.outS <= src.durationS + eps) {
                errors.append(.trimOutOfBounds(index: i, momentId: id, inS: ec.inS, outS: ec.outS, durationS: src.durationS))
            }

            // 3. clip length within preset clip_s
            let length = ec.sourceLengthS
            if !(preset.clipS.min - eps <= length && length <= preset.clipS.max + eps) {
                errors.append(.clipLengthOutOfRange(index: i, momentId: id, lengthS: length, min: preset.clipS.min, max: preset.clipS.max))
            }

            // 5. transition_s = 0 exactly when cut
            if (ec.transitionIn == .cut) != (ec.transitionS == 0) {
                errors.append(.transitionMismatch(index: i, momentId: id))
            }

            // 6. speed ramps
            if let ramp = ec.speedRamp {
                if !preset.allowSpeedRamp {
                    errors.append(.speedRampNotAllowed(index: i, momentId: id))
                } else {
                    if ec.inS + ramp.overS > src.lowFpsLeadInS + eps {
                        errors.append(.speedRampOutsideLeadIn(index: i, momentId: id, leadInS: src.lowFpsLeadInS))
                    }
                    if ramp.overS > length + eps {
                        errors.append(.speedRampTooLong(index: i, momentId: id))
                    }
                }
            }

            // 7. captions
            if let caption = ec.caption {
                if !preset.captions {
                    errors.append(.captionNotAllowed(index: i, momentId: id))
                } else if !captions.contains(caption) {
                    errors.append(.captionNotInAllowedList(index: i, momentId: id, caption: caption))
                }
            }
        }

        // 4. every button clip included
        for clip in request.clips where clip.source == .button && !seen.contains(clip.momentId) {
            errors.append(.missingButtonMoment(momentId: clip.momentId))
        }

        // 8. total duration
        let total = EditTimeline.totalDurationS(spec)
        let (lo, hi) = durationBounds(request.effectiveTargetS)
        if !(lo - eps <= total && total <= hi + eps) {
            errors.append(.durationOutOfRange(totalS: total, lowS: lo, highS: hi))
        }
        return errors
    }

    public static func durationBounds(_ effectiveTargetS: Double) -> (low: Double, high: Double) {
        (effectiveTargetS * (1 - durationTolerance), effectiveTargetS * (1 + durationTolerance))
    }

    /// True when the only problem is a video shorter than the target: there wasn't enough footage.
    /// The fallback planner's output is still rendered then (a short video beats none).
    public static func onlyTooShort(_ errors: [EditSpecError]) -> Bool {
        guard errors.count == 1, case let .durationOutOfRange(total, low, _) = errors[0] else { return false }
        return total < low
    }
}
