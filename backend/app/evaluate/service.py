"""Evaluator: budget, then the fast model (2a), then the strong model (2b) only when needed (TRD 8.2)."""
import json
import logging
import time
from dataclasses import dataclass
from typing import Any

import anthropic

from app.config import Settings
from app.errors import AppError
from app.evaluate.budget import BudgetBook
from app.evaluate.models import EvaluateContext, Evaluation, ModelVerdict, Tier
from app.evaluate.prompt import SYSTEM_PROMPT, build_user_content
from app.evaluate.scoring import compute_s2, needs_strong, sanitize, should_keep

log = logging.getLogger(__name__)

MAX_TOKENS = 4000
FALLBACK_BETA = "server-side-fallback-2026-07-01"
OUTPUT_FORMAT = {"type": "json_schema", "schema": anthropic.transform_schema(ModelVerdict)}


@dataclass
class _Tier:
    name: Tier
    model: str
    effort: str
    timeout_s: float
    fallbacks: bool


class Evaluator:
    def __init__(self, client: Any, settings: Settings, budget: BudgetBook):
        self.client = client
        self.s = settings
        self.budget = budget
        self.fast = _Tier("2a", settings.STAGE2A_MODEL, settings.STAGE2A_EFFORT, settings.STAGE2A_TIMEOUT_S, settings.STAGE2A_FALLBACKS)
        self.strong = _Tier("2b", settings.STAGE2B_MODEL, settings.STAGE2B_EFFORT, settings.STAGE2B_TIMEOUT_S, settings.STAGE2B_FALLBACKS)

    async def _ask(self, tier: _Tier, user: list[dict], frame_count: int) -> ModelVerdict:
        """One model call. Every failure, including a refusal or unusable output, raises AppError."""
        extra: dict[str, Any] = {"betas": [FALLBACK_BETA], "fallbacks": "default"} if tier.fallbacks else {}
        try:
            response = await self.client.beta.messages.create(
                model=tier.model,
                max_tokens=MAX_TOKENS,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": user}],
                thinking={"type": "adaptive"},
                output_config={"effort": tier.effort, "format": OUTPUT_FORMAT},
                timeout=tier.timeout_s,
                **extra,
            )
        except anthropic.APITimeoutError as e:
            raise AppError(504, "upstream_timeout", f"{tier.name} model timed out", retryable=True) from e
        except anthropic.APIConnectionError as e:
            raise AppError(502, "upstream_error", f"could not reach the {tier.name} model", retryable=True) from e
        except anthropic.APIStatusError as e:
            log.warning("%s model error status=%s request_id=%s", tier.name, e.status_code, e.request_id)
            raise AppError(502, "upstream_error", f"{tier.name} model returned {e.status_code}", retryable=True) from e

        if response.stop_reason == "refusal":
            raise AppError(502, "upstream_error", f"{tier.name} model declined", retryable=True)
        text = next((b.text for b in response.content if b.type == "text"), None)
        try:
            return sanitize(json.loads(text or ""), frame_count)
        except ValueError as e:  # json.JSONDecodeError is a ValueError too
            raise AppError(502, "upstream_error", f"{tier.name} model output unusable: {e}", retryable=True) from e

    async def evaluate(self, ctx: EvaluateContext, frames: list[bytes]) -> Evaluation:
        start = time.monotonic()
        describe = ctx.purpose == "describe"
        if describe:
            self.budget.take_describe(ctx.trip_id)
        else:
            self.budget.take_select(ctx.trip_id)

        user = build_user_content(ctx, frames)
        novelty = ctx.local.novelty
        tier: Tier = "2a"
        verdict: ModelVerdict | None = None
        error: AppError | None = None
        try:
            verdict = await self._ask(self.fast, user, len(frames))
        except AppError as e:
            error = e

        escalate = verdict is None or needs_strong(verdict, compute_s2(verdict, novelty, self.s.S2_WEIGHTS), self.s)
        if not describe and escalate and self.budget.try_strong(ctx.trip_id):
            try:
                verdict, tier = await self._ask(self.strong, user, len(frames)), "2b"
            except AppError as e:
                if verdict is None:
                    error = e  # report the later failure; both tiers failed

        if verdict is None:
            assert error is not None
            raise error

        s2 = compute_s2(verdict, novelty, self.s.S2_WEIGHTS)
        keep = describe or should_keep(verdict, s2, self.s)
        latency_ms = int((time.monotonic() - start) * 1000)
        # Never log frames or descriptions (TRD 11.3).
        log.info(
            "evaluate trip=%s purpose=%s tier=%s latency_ms=%d keep=%s s2=%.3f",
            ctx.trip_id, ctx.purpose, tier, latency_ms, keep, s2,
        )
        return Evaluation(keep=keep, s2=s2, tier=tier, latency_ms=latency_ms, verdict=verdict)
