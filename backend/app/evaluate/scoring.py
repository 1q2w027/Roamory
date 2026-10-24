"""S2, the keep rule, 2b escalation and cleanup of model output (TRD 8.2)."""
from typing import Any, get_args

from app.config import Settings
from app.evaluate.models import EventType, ModelVerdict, SaveDecision

SCORE_FIELDS = ("preference_alignment", "visual_interest", "significance", "visual_quality")
REQUIRED = set(ModelVerdict.model_fields)
MAX_TEXT = 200  # plan_request clips[].description maxLength
WINDOW_MAX_S = 30


def compute_s2(v: ModelVerdict, novelty: float, weights: dict[str, float]) -> float:
    s2 = (
        weights["pref"] * v.preference_alignment
        + weights["interest"] * v.visual_interest
        + weights["significance"] * v.significance
        + weights["quality"] * v.visual_quality
        + weights["novelty"] * novelty
    )
    return round(min(max(s2, 0.0), 1.0), 3)


def should_keep(v: ModelVerdict, s2: float, s: Settings) -> bool:
    return (v.save_decision == "save" and s2 >= s.SAVE_THRESHOLD) or s2 >= s.SAVE_ANYWAY_THRESHOLD


def needs_strong(v: ModelVerdict, s2: float, s: Settings) -> bool:
    return v.save_decision == "uncertain" or abs(s2 - s.SAVE_THRESHOLD) <= s.UNCERTAIN_BAND


def _clamp(x: Any, lo: float, hi: float) -> float:
    return min(max(float(x), lo), hi)


def _words(text: Any, n: int) -> str:
    return " ".join(str(text).split()[:n])[:MAX_TEXT]


def sanitize(raw: Any, frame_count: int) -> ModelVerdict:
    """Clamp scores, coerce enums and truncate text so a sloppy answer still yields a valid verdict.

    Raises ValueError when the answer is not an object, lacks a field, or has a field of the wrong type.
    """
    if not isinstance(raw, dict):
        raise ValueError("verdict must be a JSON object")
    missing = REQUIRED - raw.keys()
    if missing:
        raise ValueError(f"verdict is missing {sorted(missing)}")
    try:
        window = raw["window_hint_s"]
        fixed = {
            **{k: raw[k] for k in REQUIRED},
            **{k: _clamp(raw[k], 0.0, 1.0) for k in SCORE_FIELDS},
            "event_type": raw["event_type"] if raw["event_type"] in get_args(EventType) else "other",
            "save_decision": raw["save_decision"] if raw["save_decision"] in get_args(SaveDecision) else "uncertain",
            "best_frame_index": int(_clamp(raw["best_frame_index"], 0, max(frame_count - 1, 0))),
            "window_hint_s": {
                "pre": int(_clamp(window["pre"], 0, WINDOW_MAX_S)),
                "post": int(_clamp(window["post"], 0, WINDOW_MAX_S)),
            },
            "description": _words(raw["description"], 20),
            "reason": _words(raw["reason"], 25),
        }
    except (TypeError, KeyError) as e:
        raise ValueError(f"verdict has a malformed field: {e}") from e
    return ModelVerdict.model_validate(fixed)
