import pytest

from app.config import Settings
from app.evaluate.scoring import compute_s2, needs_strong, sanitize, should_keep
from tests.conftest import verdict

S = Settings(_env_file=None)
W = S.S2_WEIGHTS


def test_s2_matches_trd_weights():
    assert compute_s2(verdict(), novelty=0.4, weights=W) == 0.66


def test_keep_rules():
    assert should_keep(verdict(), 0.66, S) is True
    assert should_keep(verdict(save_decision="skip"), 0.66, S) is False
    assert should_keep(verdict(save_decision="skip"), 0.75, S) is True
    assert should_keep(verdict(), 0.59, S) is False


def test_needs_strong_band_and_uncertain():
    assert needs_strong(verdict(), 0.66, S) is True  # |0.66 - 0.60| <= 0.08
    assert needs_strong(verdict(), 0.86, S) is False
    assert needs_strong(verdict(save_decision="uncertain"), 0.95, S) is True


def test_sanitize_clamps_and_truncates():
    raw = verdict().model_dump() | {
        "visual_interest": 1.3,
        "significance": -0.2,
        "best_frame_index": 2,
        "event_type": "temple",
        "save_decision": "maybe",
        "window_hint_s": {"pre": 90, "post": -5},
        "description": " ".join(["word"] * 60),
    }
    v = sanitize(raw, frame_count=1)
    assert (v.visual_interest, v.significance, v.best_frame_index) == (1.0, 0.0, 0)
    assert (v.event_type, v.save_decision) == ("other", "uncertain")
    assert (v.window_hint_s.pre, v.window_hint_s.post) == (30, 0)
    assert len(v.description.split()) == 20 and len(v.description) <= 200


def test_sanitize_rejects_non_object():
    with pytest.raises(ValueError):
        sanitize(["not", "a", "dict"], frame_count=3)


def test_sanitize_rejects_missing_key():
    raw = verdict().model_dump()
    del raw["description"]
    with pytest.raises(ValueError):
        sanitize(raw, frame_count=3)
