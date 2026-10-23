"""Validate style_presets.json and every file in examples/ against its schema.

Usage: pip install jsonschema && python contracts/check.py
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

HERE = Path(__file__).parent
SCHEMA_FOR_PREFIX = {
    "plan_request_": "plan_request.schema.json",
    "edit_spec_": "edit_spec.schema.json",
    "error_": "error.schema.json",
    "clip_sidecar_": "clip_sidecar.schema.json",
}


def validate(instance_path: Path, schema_name: str) -> bool:
    schema = json.loads((HERE / schema_name).read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema, format_checker=FormatChecker())
    errors = list(validator.iter_errors(json.loads(instance_path.read_text())))
    for e in errors:
        print(f"FAIL {instance_path.relative_to(HERE)}: {'/'.join(map(str, e.path))}: {e.message}")
    if not errors:
        print(f"ok   {instance_path.relative_to(HERE)}")
    return not errors


def main() -> int:
    ok = validate(HERE / "style_presets.json", "style_presets.schema.json")
    for path in sorted((HERE / "examples").glob("*.json")):
        schema = next((s for p, s in SCHEMA_FOR_PREFIX.items() if path.name.startswith(p)), None)
        if schema is None:
            print(f"FAIL {path.name}: no schema for this file name")
            ok = False
            continue
        ok &= validate(path, schema)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
