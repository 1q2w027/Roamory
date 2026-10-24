"""Validate style_presets.json and every file in examples/ against its schema.

Also checks what the schemas cannot: a studio request's clip ids are unique, and the example studio result follows
the studio result rules against the studio request of the same style (README).

Usage: pip install jsonschema && python contracts/check.py
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

HERE = Path(__file__).parent
SCHEMA_FOR_PREFIX = {
    "error_": "error.schema.json",
    "evaluate_context_": "evaluate_context.schema.json",
    "evaluation_": "evaluation.schema.json",
    "studio_request_": "studio_request.schema.json",
    "studio_job_": "studio_job.schema.json",
    "studio_result_": "studio_result.schema.json",
}

# Every schema, keyed by its $id, so "$ref": "error.schema.json" resolves locally.
REGISTRY = Registry().with_resources(
    (schema["$id"], Resource.from_contents(schema))
    for schema in (json.loads(p.read_text()) for p in HERE.glob("*.schema.json"))
)


def studio_effective_target_s(request: dict) -> float:
    """README "Studio effective target"."""
    preset = json.loads((HERE / "style_presets.json").read_text())["presets"][request["style"]]
    overhead = preset["title_s"] + preset["end_card_s"]
    footage = sum(c["duration_s"] for c in request["clips"])
    floor = len(request["clips"]) * preset["clip_s"]["min"] + overhead
    return min(max(preset["target_s"]["default"], floor), footage + overhead)


def studio_request_errors(request: dict) -> list[str]:
    ids = [c["clip_id"] for c in request["clips"]]
    return [f"clip_id {i} repeats" for i in sorted(set(ids)) if ids.count(i) > 1]


def studio_result_errors(result: dict, request_name: str) -> list[str]:
    """README "Studio result rules" 1-4, against the studio request example of the same style."""
    request = json.loads((HERE / "examples" / request_name).read_text())
    clip_ids = [c["clip_id"] for c in request["clips"]]
    ids = [m["clip_id"] for m in result["moments"]]
    errors = [f"clip_id {i} is not a clip in {request_name}" for i in ids if i not in clip_ids]
    errors += [f"clip_id {i} repeats" for i in sorted(set(ids)) if ids.count(i) > 1]
    errors += [f"clip {i} is missing" for i in clip_ids if i not in ids]
    for m in result["moments"]:
        if not m["start_s"] < m["end_s"] <= result["total_s"] + 1e-6:
            errors.append(f"{m['clip_id']}: [{m['start_s']}, {m['end_s']}] is not inside the video")
    if [m["start_s"] for m in result["moments"]] != sorted(m["start_s"] for m in result["moments"]):
        errors.append("moments are not in playback order")
    target = studio_effective_target_s(request)
    if abs(result["total_s"] - target) > 0.1 * target:
        errors.append(f"total_s {result['total_s']} is not within 10 % of the effective target {target}")
    return errors


def validate(instance_path: Path, schema_name: str, extra=None) -> bool:
    schema = json.loads((HERE / schema_name).read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, registry=REGISTRY, format_checker=FormatChecker())
    instance = json.loads(instance_path.read_text())
    errors = [f"{'/'.join(map(str, e.path))}: {e.message}" for e in validator.iter_errors(instance)]
    if not errors and extra:
        errors = extra(instance)
    for e in errors:
        print(f"FAIL {instance_path.relative_to(HERE)}: {e}")
    if not errors:
        print(f"ok   {instance_path.relative_to(HERE)}")
    return not errors


def main() -> int:
    ok = validate(HERE / "style_presets.json", "style_presets.schema.json")
    for path in sorted((HERE / "examples").glob("*.json")):
        prefix = next((p for p in SCHEMA_FOR_PREFIX if path.name.startswith(p)), None)
        if prefix is None:
            print(f"FAIL {path.name}: no schema for this file name")
            ok = False
            continue
        extra = studio_request_errors if prefix == "studio_request_" else None
        if prefix == "studio_result_":
            request_name = path.name.replace("studio_result_", "studio_request_")
            extra = lambda result, name=request_name: studio_result_errors(result, name)
        ok &= validate(path, SCHEMA_FOR_PREFIX[prefix], extra)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
