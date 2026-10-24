"""Validate style_presets.json and every file in examples/ against its schema.

Also checks what the schemas cannot: an agent request's clips are consistent and its example
result follows the agent result rules.

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
    "clip_sidecar_": "clip_sidecar.schema.json",
    "render_job_": "render_job.schema.json",
    "evaluate_context_": "evaluate_context.schema.json",
    "evaluation_": "evaluation.schema.json",
    "agent_request_": "agent_request.schema.json",
    "agent_result_": "agent_result.schema.json",
}

# Every schema, keyed by its $id, so "$ref": "error.schema.json" resolves locally.
REGISTRY = Registry().with_resources(
    (schema["$id"], Resource.from_contents(schema))
    for schema in (json.loads(p.read_text()) for p in HERE.glob("*.schema.json"))
)


def agent_request_errors(request: dict) -> list[str]:
    """README "Agent request rules" 1-2."""
    ids = [c["moment_id"] for c in request["clips"]]
    errors = [f"moment_id {i} repeats" for i in sorted(set(ids)) if ids.count(i) > 1]
    for c in request["clips"]:
        if not 0 <= c["proposed_in_s"] < c["proposed_out_s"] <= c["duration_s"] + 1e-6:
            errors.append(f"{c['moment_id']}: proposed [{c['proposed_in_s']}, {c['proposed_out_s']}] outside the clip's {c['duration_s']} s")
    return errors


def agent_result_errors(result: dict, request_name: str) -> list[str]:
    """README "Agent result rules" 1-4, against the agent request example of the same style."""
    request = json.loads((HERE / "examples" / request_name).read_text())
    clips = {c["moment_id"]: c for c in request["clips"]}
    ids = [m["moment_id"] for m in result["moments"]]
    errors = [f"moment_id {i} is not in {request_name}" for i in ids if i not in clips]
    errors += [f"moment_id {i} repeats" for i in sorted(set(ids)) if ids.count(i) > 1]
    errors += [f"button clip {i} is missing" for i, c in clips.items() if c["source"] == "button" and i not in ids]
    for m in result["moments"]:
        if not m["start_s"] < m["end_s"] <= result["total_s"] + 1e-6:
            errors.append(f"{m['moment_id']}: [{m['start_s']}, {m['end_s']}] is not inside the video")
    if [m["start_s"] for m in result["moments"]] != sorted(m["start_s"] for m in result["moments"]):
        errors.append("moments are not in playback order")
    target = request["effective_target_s"]
    if abs(result["total_s"] - target) > 0.1 * target:
        errors.append(f"total_s {result['total_s']} is not within 10 % of effective_target_s {target}")
    return errors


EXTRA_CHECKS = {
    "agent_request_": agent_request_errors,
}


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
        extra = EXTRA_CHECKS.get(prefix)
        if prefix == "agent_result_":
            request_name = path.name.replace("agent_result_", "agent_request_")
            extra = lambda result, name=request_name: agent_result_errors(result, name)
        ok &= validate(path, SCHEMA_FOR_PREFIX[prefix], extra)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
