"""Evaluator: budget, then one call to the evaluation model (TRD 8.2)."""
import json
import logging
import time
from typing import Any

import anthropic

from app.config import Settings
from app.errors import AppError
from app.evaluate.budget import BudgetBook
from app.evaluate.models import EvaluateContext, Evaluation, ModelVerdict
from app.evaluate.prompt import SYSTEM_PROMPT, build_user_content
from app.evaluate.verdict import sanitize, should_keep


def make_client(settings: Settings) -> anthropic.AsyncAnthropic:
    # No SDK retries: the phone has its own timeout.
    return anthropic.AsyncAnthropic(
        api_key=settings.ANTHROPIC_API_KEY or None,
        timeout=settings.STAGE2A_TIMEOUT_S,
        max_retries=0,
    )


log = logging.getLogger(__name__)

MAX_TOKENS = 4000
OUTPUT_FORMAT = {"type": "json_schema", "schema": anthropic.transform_schema(ModelVerdict)}


class Evaluator:
    def __init__(self, client: Any, settings: Settings, budget: BudgetBook):
        self.client = client
        self.s = settings
        self.budget = budget

    async def _ask(self, user: list[dict], frame_count: int) -> ModelVerdict:
        """One model call. Every failure, including a refusal or unusable output, raises AppError."""
        try:
            response = await self.client.beta.messages.create(
                model=self.s.STAGE2A_MODEL,
                max_tokens=MAX_TOKENS,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user}],
                thinking={"type": "adaptive"},
                output_config={"effort": self.s.STAGE2A_EFFORT, "format": OUTPUT_FORMAT},
                timeout=self.s.STAGE2A_TIMEOUT_S,
            )
        except anthropic.APITimeoutError as e:
            raise AppError(504, "upstream_timeout", "evaluation model timed out", retryable=True) from e
        except anthropic.APIConnectionError as e:
            raise AppError(502, "upstream_error", "could not reach the evaluation model", retryable=True) from e
        except anthropic.APIStatusError as e:
            log.warning("evaluation model error status=%s request_id=%s", e.status_code, e.request_id)
            raise AppError(502, "upstream_error", f"evaluation model returned {e.status_code}", retryable=True) from e

        if response.stop_reason == "refusal":
            raise AppError(502, "upstream_error", "evaluation model declined", retryable=True)
        text = next((b.text for b in response.content if b.type == "text"), None)
        try:
            return sanitize(json.loads(text or ""), frame_count)
        except ValueError as e:  # json.JSONDecodeError is a ValueError too
            raise AppError(502, "upstream_error", f"evaluation model output unusable: {e}", retryable=True) from e

    async def evaluate(self, ctx: EvaluateContext, frames: list[bytes]) -> Evaluation:
        start = time.monotonic()
        describe = ctx.purpose == "describe"
        if describe:
            self.budget.take_describe(ctx.trip_id)
        else:
            self.budget.take_select(ctx.trip_id)

        verdict = await self._ask(build_user_content(ctx, frames), len(frames))
        keep = describe or should_keep(verdict)
        latency_ms = int((time.monotonic() - start) * 1000)
        # Never log frames or descriptions (TRD 11.3).
        log.info(
            "evaluate trip=%s purpose=%s latency_ms=%d keep=%s decision=%s",
            ctx.trip_id, ctx.purpose, latency_ms, keep, verdict.save_decision,
        )
        return Evaluation(keep=keep, latency_ms=latency_ms, verdict=verdict)
