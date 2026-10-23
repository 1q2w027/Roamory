"""Planner: one model call, validation, one repair retry (docs/video-generation-plan.md, Phase 1)."""
import json
import logging
from typing import Any

import anthropic
from pydantic import ValidationError

from app.config import Settings
from app.errors import AppError
from app.plan.models import EditSpec, PlanRequest, StylePreset
from app.plan.prompt import SYSTEM_PROMPT, TOOL_NAME, build_user_content, tool_definition
from app.plan.validate import validate_spec

log = logging.getLogger(__name__)

MAX_ATTEMPTS = 2  # first try + one repair
MAX_TOKENS = 16000
FALLBACK_BETA = "server-side-fallback-2026-07-01"

# Strict tool use cannot express numeric/string bounds; transform_schema moves them into
# descriptions, and validate_spec plus Pydantic enforce them here.
TOOL = tool_definition(anthropic.transform_schema(EditSpec))


def make_client(settings: Settings) -> anthropic.AsyncAnthropic:
    # No SDK retries: the phone has its own timeout and falls back on any error.
    return anthropic.AsyncAnthropic(
        api_key=settings.ANTHROPIC_API_KEY or None,
        timeout=settings.PLAN_TIMEOUT_S,
        max_retries=0,
    )


def normalize(raw: dict[str, Any], req: PlanRequest, preset: StylePreset) -> dict[str, Any]:
    """Fields that are pure copies of the request and preset are set here, not trusted from the model."""
    return {
        **raw,
        "trip_id": req.trip_id,
        "style": req.style,
        "output": preset.output.model_dump(),
        "music": {
            "track": preset.music_track,
            "gain_db": preset.music_gain_db,
            "duck_original_audio": not preset.keep_original_audio,
        },
    }


def check_tool_input(raw: Any, req: PlanRequest, preset: StylePreset) -> tuple[EditSpec | None, list[str]]:
    if not isinstance(raw, dict):
        return None, ["tool input must be a JSON object"]
    try:
        spec = EditSpec.model_validate(normalize(raw, req, preset))
    except ValidationError as e:
        return None, [f"{'.'.join(map(str, err['loc']))}: {err['msg']}" for err in e.errors()]
    return spec, validate_spec(spec, req, preset)


class Planner:
    def __init__(self, client: Any, settings: Settings):
        self.client = client
        self.settings = settings

    async def _call(self, messages: list[dict]) -> Any:
        try:
            return await self.client.beta.messages.create(
                model=self.settings.PLANNER_MODEL,
                max_tokens=MAX_TOKENS,
                system=SYSTEM_PROMPT,
                messages=messages,
                tools=[TOOL],
                tool_choice={"type": "auto"},  # forced tool_choice is rejected on current models
                thinking={"type": "adaptive"},
                output_config={"effort": self.settings.PLANNER_EFFORT},
                betas=[FALLBACK_BETA],
                fallbacks="default",
            )
        except anthropic.APITimeoutError as e:
            raise AppError(504, "upstream_timeout", "model API timed out", retryable=True) from e
        except anthropic.APIConnectionError as e:
            raise AppError(502, "upstream_error", "could not reach model API", retryable=True) from e
        except anthropic.APIStatusError as e:
            log.warning("model API error status=%s request_id=%s", e.status_code, e.request_id)
            raise AppError(502, "upstream_error", f"model API returned {e.status_code}", retryable=True) from e

    async def plan(self, req: PlanRequest, preset: StylePreset, images: dict[str, list[bytes]]) -> EditSpec:
        messages: list[dict] = [{"role": "user", "content": build_user_content(req, preset, images)}]
        errors: list[str] = []

        for attempt in range(1, MAX_ATTEMPTS + 1):
            response = await self._call(messages)
            if response.stop_reason == "refusal":
                errors = ["model declined the request"]
                break

            tool_uses = [b for b in response.content if b.type == "tool_use"]
            submit = next((b for b in tool_uses if b.name == TOOL_NAME), None)
            if submit is None:
                errors = [f"no {TOOL_NAME} call (stop_reason={response.stop_reason})"]
            else:
                spec, errors = check_tool_input(submit.input, req, preset)
                if spec is not None and not errors:
                    log.info("plan ok trip=%s attempt=%d clips=%d", req.trip_id, attempt, len(spec.clips))
                    return spec

            # Every tool_use needs a tool_result; the errors go back on the submit call.
            repair: list[dict] = [
                {
                    "type": "tool_result",
                    "tool_use_id": b.id,
                    "is_error": True,
                    "content": (
                        "The edit spec is invalid. Fix these and call the tool again:\n- " + "\n- ".join(errors)
                        if b is submit
                        else f"Unknown tool; call {TOOL_NAME} only."
                    ),
                }
                for b in tool_uses
            ]
            if submit is None:
                repair.append({"type": "text", "text": f"You must call {TOOL_NAME} with the edit spec."})

            log.info("plan invalid trip=%s attempt=%d errors=%s", req.trip_id, attempt, json.dumps(errors))
            messages += [
                {"role": "assistant", "content": response.content},
                {"role": "user", "content": repair},
            ]

        raise AppError(
            422,
            "invalid_plan",
            f"Edit spec failed validation after one repair attempt: {'; '.join(errors)}",
            retryable=False,
        )
