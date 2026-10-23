import pytest

from app.config import REPO_ROOT
from app.plan.models import EditSpec, PlanRequest, load_presets
from app.plan.validate import validate_spec
from tests.conftest import STYLES, load_example

PRESETS = load_presets(REPO_ROOT / "contracts" / "style_presets.json")


def test_presets_cover_every_style():
    assert sorted(PRESETS.presets) == sorted(STYLES)


@pytest.mark.parametrize("style", STYLES)
def test_plan_request_round_trip(style):
    raw = load_example(f"plan_request_{style}.json")
    assert PlanRequest.model_validate(raw).model_dump(mode="json", by_alias=True) == raw


@pytest.mark.parametrize("style", STYLES)
def test_edit_spec_round_trip(style):
    raw = load_example(f"edit_spec_{style}.json")
    assert EditSpec.model_validate(raw).model_dump(mode="json", by_alias=True) == raw


@pytest.mark.parametrize("style", STYLES)
def test_examples_pass_validator(style):
    req = PlanRequest.model_validate(load_example(f"plan_request_{style}.json"))
    spec = EditSpec.model_validate(load_example(f"edit_spec_{style}.json"))
    assert validate_spec(spec, req, PRESETS.presets[style]) == []
