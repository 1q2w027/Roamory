"""Edit spec rules from contracts/README.md ("Edit spec rules"). Keep in step with the phone's EditSpecValidator."""
from app.plan.models import EditClip, EditSpec, PlanRequest, StylePreset

EPS = 1e-6
DURATION_TOLERANCE = 0.10


def clip_output_s(clip: EditClip) -> float:
    """Output seconds for one clip. A ramp plays its first over_s source seconds in 4 equal steps."""
    length = clip.out_s - clip.in_s
    ramp = clip.speed_ramp
    if ramp is None:
        return length
    rates = [ramp.from_ + (ramp.to - ramp.from_) * k / 3 for k in range(4)]
    return length - ramp.over_s + sum((ramp.over_s / 4) / r for r in rates)


def total_duration_s(spec: EditSpec) -> float:
    total = sum(clip_output_s(c) for c in spec.clips)
    total -= sum(c.transition_s for c in spec.clips[1:] if c.transition_in != "cut")
    return total + spec.end_card.duration_s


def allowed_captions(req: PlanRequest) -> set[str]:
    allowed = {req.destination.country, req.trip_type}
    if req.destination.city:
        allowed |= {req.destination.city, f"{req.destination.city}, {req.destination.country}"}
    allowed |= {c.description for c in req.clips if c.description}
    return allowed


def validate_spec(spec: EditSpec, req: PlanRequest, preset: StylePreset) -> list[str]:
    """Return human-readable rule violations; empty means valid."""
    errors: list[str] = []
    clips_by_id = {c.moment_id: c for c in req.clips}
    captions = allowed_captions(req)
    seen: set[str] = set()

    for i, ec in enumerate(spec.clips):
        where = f"clips[{i}] ({ec.moment_id})"
        # 1. id exists, no repeats
        src = clips_by_id.get(ec.moment_id)
        if src is None:
            errors.append(f"{where}: moment_id is not in the request")
            continue
        if ec.moment_id in seen:
            errors.append(f"{where}: moment_id appears more than once")
        seen.add(ec.moment_id)

        # 2. trims inside the clip file
        if not (0 <= ec.in_s < ec.out_s <= src.duration_s + EPS):
            errors.append(f"{where}: need 0 <= in_s < out_s <= {src.duration_s}, got in_s={ec.in_s} out_s={ec.out_s}")

        # 3. clip length within preset clip_s
        length = ec.out_s - ec.in_s
        if not (preset.clip_s.min - EPS <= length <= preset.clip_s.max + EPS):
            errors.append(
                f"{where}: length out_s - in_s = {length:.2f}s is outside clip_s [{preset.clip_s.min}, {preset.clip_s.max}]"
            )

        # 5. transition_s = 0 exactly when cut
        if (ec.transition_in == "cut") != (ec.transition_s == 0):
            errors.append(f"{where}: transition_s must be 0 exactly when transition_in is cut")

        # 6. speed ramps
        if ec.speed_ramp is not None:
            if not preset.allow_speed_ramp:
                errors.append(f"{where}: speed_ramp must be null for style {spec.style}")
            else:
                over = ec.speed_ramp.over_s
                if ec.in_s + over > src.low_fps_lead_in_s + EPS:
                    errors.append(
                        f"{where}: speed_ramp needs in_s + over_s <= low_fps_lead_in_s ({src.low_fps_lead_in_s})"
                    )
                if over > length + EPS:
                    errors.append(f"{where}: speed_ramp over_s must be <= out_s - in_s")

        # 7. captions
        if ec.caption is not None:
            if not preset.captions:
                errors.append(f"{where}: caption must be null for style {spec.style}")
            elif ec.caption not in captions:
                errors.append(f"{where}: caption {ec.caption!r} is not one of the allowed strings")

    # 4. every button clip included
    for c in req.clips:
        if c.source == "button" and c.moment_id not in seen:
            errors.append(f"missing button moment {c.moment_id}")

    # 8. total duration
    total = total_duration_s(spec)
    target = req.effective_target_s
    lo, hi = target * (1 - DURATION_TOLERANCE), target * (1 + DURATION_TOLERANCE)
    if not (lo - EPS <= total <= hi + EPS):
        errors.append(f"total duration {total:.2f}s is outside {lo:.2f}-{hi:.2f}s (effective_target_s {target} +/- 10%)")

    return errors
