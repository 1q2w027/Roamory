"""POST /v1/plan (contracts/README.md)."""
import logging
from collections import defaultdict
from typing import Annotated

from fastapi import APIRouter, Depends, Request
from pydantic import ValidationError
from starlette.datastructures import UploadFile

from app.auth import require_app_token
from app.config import Settings, get_settings
from app.errors import AppError
from app.plan.models import PlanRequest, load_presets
from app.plan.service import Planner

log = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", dependencies=[Depends(require_app_token)])

# Plans per trip_id since process start. In memory only: the backend stores no trip data (TRD §2).
_plan_counts: defaultdict[str, int] = defaultdict(int)


def get_planner(request: Request) -> Planner:
    return request.app.state.planner


async def _part_bytes(part: UploadFile | str) -> bytes:
    return await part.read() if isinstance(part, UploadFile) else part.encode()


@router.post("/plan", response_model=None)
async def plan(
    request: Request,
    settings: Annotated[Settings, Depends(get_settings)],
    planner: Annotated[Planner, Depends(get_planner)],
) -> dict:
    form = await request.form()

    raw = form.get("request")
    if raw is None:
        raise AppError(400, "bad_request", "missing 'request' part")
    try:
        req = PlanRequest.model_validate_json(await _part_bytes(raw))
    except ValidationError as e:
        raise AppError(400, "bad_request", f"invalid request JSON: {e.error_count()} error(s): {e.errors()[:3]}") from e

    ids = [c.moment_id for c in req.clips]
    if len(set(ids)) != len(ids):
        raise AppError(400, "bad_request", "clip moment_ids must be unique")
    if len(req.clips) > settings.MAX_PLAN_CLIPS:
        raise AppError(413, "too_many_clips", f"{len(req.clips)} clips; the limit is {settings.MAX_PLAN_CLIPS}")

    expected = {f"{c.moment_id}_{k}.jpg": c.moment_id for c in req.clips for k in range(c.thumbnail_count)}
    sent = {name for name in form.keys() if name != "request"}
    if sent != set(expected):
        missing, extra = sorted(set(expected) - sent), sorted(sent - set(expected))
        raise AppError(400, "bad_request", f"thumbnail parts don't match thumbnail_count: missing={missing} extra={extra}")

    images: dict[str, list[bytes]] = defaultdict(list)
    for c in req.clips:
        for k in range(c.thumbnail_count):
            part = form.get(f"{c.moment_id}_{k}.jpg")
            if not isinstance(part, UploadFile):
                raise AppError(400, "bad_request", f"{c.moment_id}_{k}.jpg must be a file part")
            images[c.moment_id].append(await part.read())

    if _plan_counts[req.trip_id] >= settings.PLANS_PER_TRIP:
        raise AppError(429, "rate_limited", f"over {settings.PLANS_PER_TRIP} plans for this trip")
    _plan_counts[req.trip_id] += 1

    preset = load_presets(settings.STYLE_PRESETS_PATH).presets[req.style]
    log.info("plan trip=%s style=%s clips=%d images=%d", req.trip_id, req.style, len(req.clips), len(expected))
    spec = await planner.plan(req, preset, images)
    return spec.model_dump(mode="json", by_alias=True)
