#!/usr/bin/env bash
# Copies contracts/style_presets.json into the bundle. Run after the contract changes;
# ContractsTests fails while the copies differ.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cp "$here/../../contracts/style_presets.json" "$here/Sources/RoamoryKit/Resources/style_presets.json"
