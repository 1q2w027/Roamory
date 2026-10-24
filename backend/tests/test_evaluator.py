import anthropic
import httpx
import pytest

from app.errors import AppError
from app.evaluate.budget import BudgetBook
from app.evaluate.models import EvaluateContext
from app.evaluate.prompt import build_user_content
from app.evaluate.service import Evaluator
from tests.conftest import JPEG, load_example, ok, text_response

pytestmark = pytest.mark.anyio

ctx = EvaluateContext.model_validate(load_example("evaluate_context_select.json"))
describe_ctx = EvaluateContext.model_validate(load_example("evaluate_context_describe.json"))
frames3 = [JPEG] * 3


def timeout() -> anthropic.APITimeoutError:
    return anthropic.APITimeoutError(request=httpx.Request("POST", "https://api"))


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def budget(settings):
    return BudgetBook(settings)


@pytest.fixture
def evaluator(fake_model, settings, budget):
    return Evaluator(fake_model, settings, budget)


async def test_save_is_kept_with_one_call(evaluator, fake_model):
    fake_model.responses = [ok()]
    r = await evaluator.evaluate(ctx, frames3)
    assert (r.keep, len(fake_model.calls)) == (True, 1)
    assert fake_model.calls[0]["model"] == "claude-haiku-5-5"
    assert "fallbacks" not in fake_model.calls[0]


async def test_skip_is_not_kept(evaluator, fake_model):
    fake_model.responses = [ok(save_decision="skip")]
    r = await evaluator.evaluate(ctx, frames3)
    assert (r.keep, len(fake_model.calls)) == (False, 1)


async def test_timeout_raises_504(evaluator, fake_model):
    fake_model.responses = [timeout()]
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert (e.value.status, e.value.code, e.value.retryable) == (504, "upstream_timeout", True)
    assert len(fake_model.calls) == 1


async def test_unusable_output_raises_502(evaluator, fake_model):
    fake_model.responses = [text_response("nope")]
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert (e.value.status, e.value.code, e.value.retryable) == (502, "upstream_error", True)
    assert len(fake_model.calls) == 1


async def test_refusal_raises_502(evaluator, fake_model):
    refusal = text_response("")
    refusal.stop_reason = "refusal"
    fake_model.responses = [refusal]
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert e.value.status == 502


async def test_describe_always_keeps(evaluator, fake_model):
    fake_model.responses = [ok(save_decision="skip")]
    r = await evaluator.evaluate(describe_ctx, frames3)
    assert (r.keep, len(fake_model.calls)) == (True, 1)


async def test_select_over_budget_makes_no_call(evaluator, fake_model, budget):
    for _ in range(5):
        budget.take_select(ctx.trip_id)
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert e.value.status == 429 and fake_model.calls == []


async def test_request_uses_structured_output_and_timeouts(evaluator, fake_model, settings):
    fake_model.responses = [ok()]
    await evaluator.evaluate(ctx, frames3)
    call = fake_model.calls[0]
    assert call["output_config"]["format"]["type"] == "json_schema"
    assert call["output_config"]["effort"] == settings.STAGE2A_EFFORT
    assert call["timeout"] == settings.STAGE2A_TIMEOUT_S
    assert call["thinking"] == {"type": "adaptive"}


def test_prompt_excludes_identifiers():
    blocks = build_user_content(ctx, frames3)
    text = " ".join(b.get("text", "") for b in blocks)
    assert ctx.trip_id not in text and ctx.install_id not in text
    assert [b["type"] for b in blocks].count("image") == 3
    assert "Kyoto" in text and "honeymoon" in text


def test_prompt_sends_every_saved_description():
    many = ctx.model_copy(update={"recent_descriptions": [f"saved moment {i}" for i in range(40)]})
    text = " ".join(b.get("text", "") for b in build_user_content(many, frames3))
    assert all(f"saved moment {i}\"" in text for i in range(40))
