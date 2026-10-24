"""POST /v1/evaluate (contracts/README.md)."""
from typing import Annotated

from fastapi import APIRouter, Depends, Request
from pydantic import ValidationError
from starlette.datastructures import UploadFile

from app.auth import require_app_token
from app.config import Settings, get_settings
from app.errors import AppError
from app.evaluate.models import EvaluateContext
from app.evaluate.service import Evaluator

router = APIRouter(prefix="/v1", dependencies=[Depends(require_app_token)])

MAX_FRAMES = 3
JPEG_MAGIC = b"\xff\xd8\xff"


def get_evaluator(request: Request) -> Evaluator:
    return request.app.state.evaluator


async def _part_bytes(part: UploadFile | str) -> bytes:
    return await part.read() if isinstance(part, UploadFile) else part.encode()


@router.post("/evaluate", response_model=None)
async def evaluate(
    request: Request,
    settings: Annotated[Settings, Depends(get_settings)],
    evaluator: Annotated[Evaluator, Depends(get_evaluator)],
) -> dict:
    # Everything is validated before the evaluator runs, so a bad request spends no budget.
    form = await request.form()

    raw = form.get("context")
    if raw is None:
        raise AppError(400, "bad_request", "missing 'context' part")
    try:
        ctx = EvaluateContext.model_validate_json(await _part_bytes(raw))
    except ValidationError as e:
        raise AppError(400, "bad_request", f"invalid context JSON: {e.error_count()} error(s): {e.errors()[:3]}") from e

    sent = sorted(name for name in form.keys() if name != "context")
    n = len(sent)
    if not 1 <= n <= MAX_FRAMES or sent != [f"frame_{k}.jpg" for k in range(n)]:
        raise AppError(400, "bad_request", f"expected parts frame_0.jpg .. frame_{{n-1}}.jpg with n = 1..{MAX_FRAMES}; got {sent}")

    frames: list[bytes] = []
    for name in sent:
        part = form.get(name)
        if not isinstance(part, UploadFile):
            raise AppError(400, "bad_request", f"{name} must be a file part")
        data = await part.read()
        if not data.startswith(JPEG_MAGIC):
            raise AppError(400, "bad_request", f"{name} is not a JPEG")
        if len(data) > settings.MAX_FRAME_BYTES:
            raise AppError(400, "bad_request", f"{name} is {len(data)} bytes; the limit is {settings.MAX_FRAME_BYTES}")
        frames.append(data)

    result = await evaluator.evaluate(ctx, frames)
    return result.model_dump(mode="json")
