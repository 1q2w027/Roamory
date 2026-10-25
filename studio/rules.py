"""Studio rules from contracts/README.md: request checks, the effective target and the result checks."""
import json
import subprocess
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from .config import CONTRACTS

_REGISTRY = Registry().with_resources(
    (schema["$id"], Resource.from_contents(schema))
    for schema in (json.loads(p.read_text()) for p in CONTRACTS.glob("*.schema.json"))
)


def _validator(name: str) -> Draft202012Validator:
    return Draft202012Validator(json.loads((CONTRACTS / name).read_text()), registry=_REGISTRY,
                                format_checker=FormatChecker())


_REQUEST = _validator("studio_request.schema.json")
_RESULT = _validator("studio_result.schema.json")


def preset(style: str) -> dict:
    return json.loads((CONTRACTS / "style_presets.json").read_text())["presets"][style]


def request_errors(request) -> list[str]:
    errors = [f"{'/'.join(map(str, e.path)) or 'request'}: {e.message}" for e in _REQUEST.iter_errors(request)]
    if errors:
        return errors
    ids = [c["clip_id"] for c in request["clips"]]
    return [f"clip_id {i} repeats" for i in sorted(set(ids)) if ids.count(i) > 1]


def effective_target_s(request: dict) -> float:
    """README "Studio effective target"."""
    p = preset(request["style"])
    overhead = p["title_s"] + p["end_card_s"]
    footage = sum(c["duration_s"] for c in request["clips"])
    floor = len(request["clips"]) * p["clip_s"]["min"] + overhead
    return round(min(max(p["target_s"]["default"], floor), footage + overhead), 3)


def probe(video: Path) -> dict | None:
    """Duration and stream types of a video, or None if ffprobe cannot read it."""
    run = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type",
                          "-of", "json", str(video)], capture_output=True, text=True)
    if run.returncode != 0:
        return None
    info = json.loads(run.stdout)
    try:
        return {"duration_s": float(info["format"]["duration"]),
                "streams": [s["codec_type"] for s in info.get("streams", [])]}
    except (KeyError, ValueError):
        return None


def result_errors(result, request: dict, video: Path) -> list[str]:
    """README "Studio result rules" 1-3, plus the video plays."""
    errors = [f"{'/'.join(map(str, e.path)) or 'result'}: {e.message}" for e in _RESULT.iter_errors(result)]
    if errors:
        return errors
    clip_ids = [c["clip_id"] for c in request["clips"]]
    ids = [m["clip_id"] for m in result["moments"]]
    errors += [f"clip_id {i} is not a clip of the request" for i in ids if i not in clip_ids]
    for m in result["moments"]:
        if not m["start_s"] < m["end_s"] <= result["total_s"] + 1e-6:
            errors.append(f"{m["clip_id"]}: [{m['start_s']}, {m['end_s']}] is not inside the video")
    starts = [m["start_s"] for m in result["moments"]]
    if starts != sorted(starts):
        errors.append("moments are not in playback order")
    target = effective_target_s(request)
    if abs(result["total_s"] - target) > 0.1 * target:
        errors.append(f"total_s {result['total_s']} is not within 10 % of the target {target}")
    info = probe(video) if video.exists() else None
    if info is None or "video" not in info["streams"]:
        errors.append(f"{video.name} is missing or has no video stream")
    elif abs(info["duration_s"] - result["total_s"]) > 0.5:
        errors.append(f"total_s {result['total_s']} differs from the file's {info['duration_s']:.3f} s by more than 0.5 s")
    return errors
