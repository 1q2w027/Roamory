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

ctx = EvaluateContext.model_validate(load_example("evaluate_context_select.json"))  # novelty 0.4
describe_ctx = EvaluateContext.model_validate(load_example("evaluate_context_describe.json"))
frames3 = [JPEG] * 3
CONFIDENT = dict(preference_alignment=0.9, visual_interest=0.9, significance=0.9, visual_quality=0.9)  # S2 0.85


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


async def test_confident_fast_answer_skips_strong(evaluator, fake_model):
    fake_model.responses = [ok(**CONFIDENT)]
    r = await evaluator.evaluate(ctx, frames3)
    assert (r.tier, r.keep, r.s2, len(fake_model.calls)) == ("2a", True, 0.85, 1)
    assert fake_model.calls[0]["model"] == "claude-haiku-5-5"


async def test_near_threshold_escalates(evaluator, fake_model):
    fake_model.responses = [ok(), ok(save_decision="skip", preference_alignment=0.2)]
    r = await evaluator.evaluate(ctx, frames3)
    assert (r.tier, r.keep, r.s2) == ("2b", False, 0.45)
    assert fake_model.calls[1]["model"] == "claude-sonnet-5-5" and fake_model.calls[1]["fallbacks"] == "default"
    assert "fallbacks" not in fake_model.calls[0]


async def test_fast_failure_escalates(evaluator, fake_model):
    fake_model.responses = [text_response("not json"), ok(**CONFIDENT)]
    assert (await evaluator.evaluate(ctx, frames3)).tier == "2b"


async def test_fast_refusal_escalates(evaluator, fake_model):
    refusal = text_response("")
    refusal.stop_reason = "refusal"
    fake_model.responses = [refusal, ok(**CONFIDENT)]
    assert (await evaluator.evaluate(ctx, frames3)).tier == "2b"


async def test_strong_timeout_returns_fast_verdict(evaluator, fake_model):
    fake_model.responses = [ok(), timeout()]
    r = await evaluator.evaluate(ctx, frames3)
    assert (r.tier, r.s2, r.keep) == ("2a", 0.66, True)


async def test_both_fail_raises_504(evaluator, fake_model):
    fake_model.responses = [timeout(), timeout()]
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert (e.value.status, e.value.code, e.value.retryable) == (504, "upstream_timeout", True)


async def test_both_unusable_raises_502(evaluator, fake_model):
    fake_model.responses = [text_response("nope"), text_response("still nope")]
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert (e.value.status, e.value.code, e.value.retryable) == (502, "upstream_error", True)


async def test_strong_budget_exhausted_returns_fast(evaluator, fake_model, budget):
    for _ in range(15):
        budget.try_strong(ctx.trip_id)
    fake_model.responses = [ok()]
    assert (await evaluator.evaluate(ctx, frames3)).tier == "2a"


async def test_describe_never_escalates_and_keeps(evaluator, fake_model):
    fake_model.responses = [ok(save_decision="skip", preference_alignment=0.0)]
    r = await evaluator.evaluate(describe_ctx, frames3)
    assert (r.keep, r.tier, len(fake_model.calls)) == (True, "2a", 1)


async def test_select_over_budget_makes_no_call(evaluator, fake_model, budget):
    for _ in range(5):
        budget.take_select(ctx.trip_id)
    with pytest.raises(AppError) as e:
        await evaluator.evaluate(ctx, frames3)
    assert e.value.status == 429 and fake_model.calls == []


async def test_request_uses_structured_output_and_timeouts(evaluator, fake_model, settings):
    fake_model.responses = [ok(**CONFIDENT)]
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
