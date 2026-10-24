import pytest

from app.evaluate.verdict import sanitize, should_keep
from tests.conftest import verdict


def test_keep_follows_the_model_decision():
    assert should_keep(verdict()) is True
    assert should_keep(verdict(save_decision="skip")) is False


def test_sanitize_coerces_and_truncates():
    raw = verdict().model_dump() | {
        "best_frame_index": 2,
        "event_type": "temple",
        "save_decision": "maybe",
        "window_hint_s": {"pre": 90, "post": -5},
        "description": " ".join(["word"] * 60),
    }
    v = sanitize(raw, frame_count=1)
    assert v.best_frame_index == 0
    assert (v.event_type, v.save_decision) == ("other", "skip")
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
