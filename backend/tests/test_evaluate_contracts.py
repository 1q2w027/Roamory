import pytest
from pydantic import ValidationError

from app.evaluate.models import EvaluateContext, Evaluation
from tests.conftest import load_example


@pytest.mark.parametrize("name", ["evaluate_context_select.json", "evaluate_context_describe.json"])
def test_context_round_trip(name):
    raw = load_example(name)
    assert EvaluateContext.model_validate(raw).model_dump(mode="json") == raw


@pytest.mark.parametrize("name", ["evaluation_save.json", "evaluation_skip.json"])
def test_evaluation_round_trip(name):
    raw = load_example(name)
    assert Evaluation.model_validate(raw).model_dump(mode="json") == raw


def test_context_rejects_unknown_field():
    raw = load_example("evaluate_context_select.json") | {"gps": [35.0, 135.7]}
    with pytest.raises(ValidationError):
        EvaluateContext.model_validate(raw)


def test_context_accepts_every_saved_description():
    raw = load_example("evaluate_context_select.json") | {"recent_descriptions": [f"d{i}" for i in range(50)]}
    assert len(EvaluateContext.model_validate(raw).recent_descriptions) == 50
