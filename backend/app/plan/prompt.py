"""System prompt and user content for the edit planner."""
import base64
import json

from app.plan.models import PlanRequest, StylePreset

TOOL_NAME = "submit_edit_spec"

SYSTEM_PROMPT = f"""\
You are the video editor for Roamory, an app that films a trip hands-free and turns the best moments into a short highlight video.

You get a style preset, the trip context, a table of candidate clips and up to 4 thumbnails per clip (evenly spaced through the clip's proposed window, labeled by moment_id). Choose and trim clips into an edit spec, then submit it by calling the {TOOL_NAME} tool exactly once. Do not answer in plain text.

Rules. A spec that breaks a hard rule is rejected.

Hard rules:
- Include every clip whose source is "button". The user pressed a button to keep it.
- Use only moment_ids from the table, each at most once.
- Trims are seconds from the start of that clip's file: 0 <= in_s < out_s <= duration_s. Start from proposed_in_s/proposed_out_s and widen or shift as needed.
- Each clip's length out_s - in_s must be within the preset's clip_s min and max.
- transition_in "cut" has transition_s 0; "fade" or "dissolve" has transition_s within the preset's transition_s range. Use the preset's transition.
- speed_ramp is null unless the preset has allow_speed_ramp. Use one only on a clip with low_fps_lead_in_s > 0, and keep in_s + over_s <= low_fps_lead_in_s and over_s <= out_s - in_s. Rates are multipliers: 4.0 is 4x fast, 1.0 is real time; a ramp usually runs from fast to 1.0.
- caption is null unless the preset has captions. When set, it must equal exactly one of: the destination city, the country, "city, country", the trip type, or one clip's description. Never write new caption text.
- Total duration must be within +/-10% of effective_target_s. Compute it as: sum of each clip's output length, minus transition_s of every clip after the first whose transition_in is not cut, plus end_card.duration_s. A clip's output length is out_s - in_s, except a ramped clip, whose first over_s source seconds play in 4 equal steps at rates r_k = from + (to - from) * k / 3 (k = 0..3), adding sum((over_s / 4) / r_k) instead of over_s. The title is overlaid and adds no time.

Editing guidance:
- When time is short, cut button clips toward clip_s min first, then add the best other clips into the time left.
- Prefer higher scores, sharp and well-composed thumbnails, and variety of event types.
- Drop near-duplicates: two clips of the same view or scene, keeping the better one (never drop a button clip).
- Order clips chronologically by t_from_ms.
- Copy output and music from the preset: music.track = music_track, music.gain_db = music_gain_db, duck_original_audio = not keep_original_audio.
- title.duration_s = preset title_s; end_card.duration_s = preset end_card_s; end_card.text = "Made with Roamory".
- Title text and subtitle use only the destination, the trip type and the start date's month and year (for example "Kyoto" / "October 2026"). Never invent events, names or places. Do not identify people.
"""


def tool_definition(input_schema: dict) -> dict:
    return {
        "name": TOOL_NAME,
        "description": "Submit the finished edit spec for this trip. Call exactly once.",
        "input_schema": input_schema,
        "strict": True,
    }


def build_user_content(req: PlanRequest, preset: StylePreset, images: dict[str, list[bytes]]) -> list[dict]:
    """Preset, trip context, clip table, then each clip's thumbnails labeled by moment_id."""
    trip = {
        "trip_id": req.trip_id,
        "style": req.style,
        "trip_type": req.trip_type,
        "destination": req.destination.model_dump(),
        "start_date": req.start_date.isoformat(),
        "target_s": req.target_s,
        "effective_target_s": req.effective_target_s,
    }
    table = [c.model_dump(exclude={"thumbnail_count"}) for c in req.clips]
    content: list[dict] = [
        {
            "type": "text",
            "text": (
                f"Style preset ({req.style}):\n{preset.model_dump_json(indent=2)}\n\n"
                f"Trip:\n{json.dumps(trip, indent=2)}\n\n"
                f"Clips:\n{json.dumps(table, indent=2)}"
            ),
        }
    ]
    for c in req.clips:
        thumbs = images.get(c.moment_id, [])
        if not thumbs:
            continue
        content.append({"type": "text", "text": f"Thumbnails for {c.moment_id}:"})
        for data in thumbs:
            content.append(
                {
                    "type": "image",
                    "source": {
                        "type": "base64",
                        "media_type": "image/jpeg",
                        "data": base64.standard_b64encode(data).decode("ascii"),
                    },
                }
            )
    content.append({"type": "text", "text": f"Plan the edit and call {TOOL_NAME}."})
    return content
