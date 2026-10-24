#!/usr/bin/env bash
# Renders each contract example (or the styles given) over the sample clips with the Remotion CLI,
# then checks each MP4 with ffprobe: size and fps match the spec, duration matches the golden
# contracts/examples/timeline_{style}.json total within 0.5 s.
# Needs ffprobe and scripts/sync-assets.sh run first. Usage: scripts/smoke.sh [style ...]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
if [ $# -gt 0 ]; then styles=("$@"); else styles=(cinematic reels documentary vlog); fi
mkdir -p out
failed=0

for style in "${styles[@]}"; do
  props="out/props_$style.json"
  video="out/smoke_$style.mp4"
  npx tsx scripts/example-props.ts "$style" >"$props"
  start=$(date +%s)
  npx remotion render src/remotion/index.ts Highlight "$video" --props="$props" --codec=h264 --log=error
  elapsed=$(($(date +%s) - start))

  IFS=, read -r width height rate < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 "$video")
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video")
  if ! node -e '
    const [style, w, h, rate, dur] = process.argv.slice(1);
    const fs = require("fs");
    const spec = JSON.parse(fs.readFileSync(`../contracts/examples/render_request_${style}.json`)).edit_spec;
    const golden = JSON.parse(fs.readFileSync(`../contracts/examples/timeline_${style}.json`)).total_s;
    const [n, d] = rate.split("/").map(Number);
    const errors = [];
    if (+w !== spec.output.width || +h !== spec.output.height) errors.push(`size ${w}x${h}, want ${spec.output.width}x${spec.output.height}`);
    if (Math.abs(n / d - spec.output.fps) > 0.01) errors.push(`fps ${rate}, want ${spec.output.fps}`);
    if (Math.abs(+dur - golden) > 0.5) errors.push(`duration ${dur} s, want ${golden} s`);
    console.log(`${errors.length ? "FAIL" : "ok  "} ${style}: ${w}x${h} ${rate} fps, ${(+dur).toFixed(3)} s (golden ${golden} s)${errors.length ? ": " + errors.join("; ") : ""}`);
    process.exit(errors.length ? 1 : 0);
  ' "$style" "$width" "$height" "$rate" "$duration"; then
    failed=1
  fi
  echo "     rendered in ${elapsed}s -> $video"
done
exit $failed
