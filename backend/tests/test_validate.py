import copy

import pytest

from app.config import REPO_ROOT
from app.plan.models import EditSpec, PlanRequest, load_presets
from app.plan.validate import clip_output_s, total_duration_s, validate_spec
from tests.conftest import load_example

PRESETS = load_presets(REPO_ROOT / "contracts" / "style_presets.json")


def check(style: str, mutate) -> list[str]:
    """Apply mutate(spec_dict, request_dict) to the style's examples and validate."""
    spec = copy.deepcopy(load_example(f"edit_spec_{style}.json"))
    req = copy.deepcopy(load_example(f"plan_request_{style}.json"))
    mutate(spec, req)
    return validate_spec(EditSpec.model_validate(spec), PlanRequest.model_validate(req), PRESETS.presets[style])


def assert_one_error(errors: list[str], fragment: str):
    assert any(fragment in e for e in errors), errors


def test_unknown_moment_id():
    def m(spec, _):
        spec["clips"][0]["moment_id"] = "m_99"

    assert_one_error(check("vlog", m), "not in the request")


def test_repeated_moment_id():
    def m(spec, _):
        spec["clips"][1]["moment_id"] = spec["clips"][0]["moment_id"]

    assert_one_error(check("vlog", m), "more than once")


def test_trim_past_clip_end():
    def m(spec, req):
        dur = next(c["duration_s"] for c in req["clips"] if c["moment_id"] == spec["clips"][0]["moment_id"])
        spec["clips"][0]["out_s"] = dur + 1
        spec["clips"][0]["in_s"] = dur - 4

    assert_one_error(check("vlog", m), "out_s <=")


def test_clip_length_outside_preset():
    def m(spec, _):
        spec["clips"][0]["out_s"] = spec["clips"][0]["in_s"] + 20

    assert_one_error(check("vlog", m), "outside clip_s")


def test_missing_button_clip():
    def m(spec, _):
        spec["clips"] = [c for c in spec["clips"] if c["moment_id"] != "m_06"]

    assert_one_error(check("vlog", m), "missing button moment m_06")


@pytest.mark.parametrize("transition_in,transition_s", [("cut", 0.5), ("fade", 0)])
def test_transition_s_matches_cut(transition_in, transition_s):
    def m(spec, _):
        spec["clips"][1]["transition_in"] = transition_in
        spec["clips"][1]["transition_s"] = transition_s

    assert_one_error(check("vlog", m), "transition_s must be 0")


def test_speed_ramp_not_allowed_for_style():
    def m(spec, _):
        spec["clips"][0]["speed_ramp"] = {"from": 2.0, "to": 1.0, "over_s": 0.5}

    assert_one_error(check("vlog", m), "speed_ramp must be null")


def test_speed_ramp_outside_low_fps_lead_in():
    def m(spec, _):
        # m_01 has low_fps_lead_in_s 0 in the reels example
        spec["clips"][0]["speed_ramp"] = {"from": 4.0, "to": 1.0, "over_s": 1.0}

    assert_one_error(check("reels", m), "low_fps_lead_in_s")


def test_caption_not_allowed_for_style():
    def m(spec, _):
        spec["clips"][0]["caption"] = "Kyoto"

    assert_one_error(check("vlog", m), "caption must be null")


def test_invented_caption():
    def m(spec, _):
        spec["clips"][0]["caption"] = "Our first night in Gion"

    assert_one_error(check("documentary", m), "not one of the allowed strings")


@pytest.mark.parametrize("caption", ["Kyoto", "Japan", "Kyoto, Japan", "honeymoon", "Bowl of ramen on a wooden counter"])
def test_allowed_captions(caption):
    def m(spec, _):
        spec["clips"][0]["caption"] = caption

    assert check("documentary", m) == []


def test_total_too_long():
    def m(spec, _):
        spec["end_card"]["duration_s"] = 20

    assert_one_error(check("vlog", m), "total duration")


def test_total_duration_counts_transitions_and_end_card():
    spec = EditSpec.model_validate(load_example("edit_spec_cinematic.json"))
    clips = sum(clip_output_s(c) for c in spec.clips)
    overlaps = sum(c.transition_s for c in spec.clips[1:] if c.transition_in != "cut")
    assert total_duration_s(spec) == pytest.approx(clips - overlaps + spec.end_card.duration_s)


def test_speed_ramp_output_length():
    spec = EditSpec.model_validate(load_example("edit_spec_reels.json"))
    ramped = next(c for c in spec.clips if c.speed_ramp)  # 3 s trim, 4.0 -> 1.0 over 1 s
    assert clip_output_s(ramped) == pytest.approx(2.0 + 0.25 * (1 / 4 + 1 / 3 + 1 / 2 + 1 / 1))
