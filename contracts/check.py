"""Validate style_presets.json and every file in examples/ against its schema.

Also checks what the schemas cannot: a render request's clips match its edit spec and the
trims fit the uploaded files, and a golden timeline lines up with its edit spec.

Usage: pip install jsonschema && python contracts/check.py
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

HERE = Path(__file__).parent
SCHEMA_FOR_PREFIX = {
    "plan_request_": "plan_request.schema.json",
    "edit_spec_": "edit_spec.schema.json",
    "error_": "error.schema.json",
    "clip_sidecar_": "clip_sidecar.schema.json",
    "render_request_": "render_request.schema.json",
    "render_job_": "render_job.schema.json",
    "timeline_": "timeline.schema.json",
}

# Every schema, keyed by its $id, so "$ref": "edit_spec.schema.json" resolves locally.
REGISTRY = Registry().with_resources(
    (schema["$id"], Resource.from_contents(schema))
    for schema in (json.loads(p.read_text()) for p in HERE.glob("*.schema.json"))
)


def rebased_errors(request: dict) -> list[str]:
    """README "Render request rules" 1-2."""
    uploads = {c["moment_id"]: c for c in request["clips"]}
    spec_ids = [c["moment_id"] for c in request["edit_spec"]["clips"]]
    errors = []
    if sorted(spec_ids) != sorted(uploads) or len(uploads) != len(request["clips"]):
        errors.append(f"clips {sorted(uploads)} do not match edit_spec.clips {sorted(spec_ids)}")
    for c in request["edit_spec"]["clips"]:
        upload = uploads.get(c["moment_id"])
        if upload and not 0 <= c["in_s"] < c["out_s"] <= upload["duration_s"] + 1e-6:
            errors.append(f"{c['moment_id']}: trim [{c['in_s']}, {c['out_s']}] outside the uploaded {upload['duration_s']} s")
    return errors


def timeline_errors(timeline: dict) -> list[str]:
    spec = json.loads((HERE / "examples" / timeline["edit_spec"]).read_text())
    slots = timeline["slots"]
    errors = []
    if [s["moment_id"] for s in slots] != [c["moment_id"] for c in spec["clips"]]:
        errors.append("slot moment_ids do not match the edit spec's clips")
    if abs(slots[-1]["end_s"] - timeline["end_card_start_s"]) > 1e-6:
        errors.append("end_card_start_s is not the last slot's end_s")
    if abs(timeline["end_card_start_s"] + spec["end_card"]["duration_s"] - timeline["total_s"]) > 1e-3:
        errors.append("total_s is not end_card_start_s + end_card.duration_s")
    return errors


EXTRA_CHECKS = {"render_request_": rebased_errors, "timeline_": timeline_errors}


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
        ok &= validate(path, SCHEMA_FOR_PREFIX[prefix], EXTRA_CHECKS.get(prefix))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
