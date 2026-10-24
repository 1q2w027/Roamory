#!/usr/bin/env bash
# Copies the shared assets into public/ (git-ignored), like ios/RoamoryKit/scripts/sync-contracts.sh:
# contracts/style_presets.json, the bundled music beds (public/music/{track}.m4a) and the sample clips
# (public/sample/, for scripts/agent-smoke.sh). Run after any of them change.
# IOS_RESOURCES overrides where the iOS bundle's Resources folder is (e.g. another checkout).
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
repo="$here/.."
resources="${IOS_RESOURCES:-$repo/ios/RoamoryKit/Sources/RoamoryKit/Resources}"

mkdir -p "$here/public/music" "$here/public/sample"
cp "$repo/contracts/style_presets.json" "$here/public/style_presets.json"

copy() { # $1 = source folder, $2 = glob, $3 = destination
  shopt -s nullglob
  local files=("$resources/$1"/$2)
  shopt -u nullglob
  if [ ${#files[@]} -eq 0 ]; then
    echo "warning: no $2 in $resources/$1; renders go without them (set IOS_RESOURCES to point elsewhere)" >&2
    return
  fi
  cp "${files[@]}" "$3/"
  echo "copied ${#files[@]} file(s) from $1"
}
copy Music '*.m4a' "$here/public/music"
copy SampleClips '*.mp4' "$here/public/sample"
