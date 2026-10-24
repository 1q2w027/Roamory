#!/usr/bin/env bash
# Agent mode end to end against a running render service (npm start, with ANTHROPIC_API_KEY set).
# Posts contracts/examples/agent_request_{style}.json with the sample clips from public/sample/ standing
# in for its moments, polls the job, fetches the result and the video, then checks with ffprobe:
# size and fps match the style preset, duration matches the result's total_s within 0.5 s, and
# total_s is within ±10% of effective_target_s.
# It spends API money, so it is never part of npm test. Needs curl, ffprobe and scripts/sync-assets.sh run first.
# Usage: scripts/agent-smoke.sh [style]   (default reels; BASE_URL overrides http://localhost:$PORT)
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
cd "$here"
style="${1:-reels}"

# Same precedence as npm start: the environment, then render/.env, then the repo-root .env.
read_env() { grep -hE "^$1=" .env ../.env 2>/dev/null | head -1 | cut -d= -f2- || true; }
token="${APP_TOKEN:-$(read_env APP_TOKEN)}"
port="${PORT:-$(read_env PORT)}"
base="${BASE_URL:-http://localhost:${port:-3000}}"
[ -n "$token" ] || { echo "APP_TOKEN is not set" >&2; exit 1; }
samples=(public/sample/*.mp4)
[ -e "${samples[0]}" ] || { echo "no sample clips in public/sample; run scripts/sync-assets.sh" >&2; exit 1; }

mkdir -p out
request="out/agent_request_$style.json"
video="out/agent_$style.mp4"
result="out/agent_result_$style.json"

# The request with each clip's duration, audio and proposed window set from the sample file it uploads.
# A fresh trip_id, so repeated runs don't hit AGENTS_PER_TRIP.
facts=()
for s in "${samples[@]}"; do
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$s")
  audio=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$s" | head -1)
  facts+=("$s,$duration,${audio:+true}")
done
node -e '
  const fs = require("fs");
  const [style, out, ...facts] = process.argv.slice(1);
  const samples = facts.map((f) => { const [file, d, a] = f.split(","); return { file, duration_s: Math.floor(+d * 10) / 10, has_audio: a === "true" }; });
  const r = JSON.parse(fs.readFileSync(`../contracts/examples/agent_request_${style}.json`));
  r.trip_id = `smoke_${Date.now()}`;
  r.clips.forEach((c, i) => {
    const s = samples[i % samples.length];
    const mid = s.duration_s / 2;
    Object.assign(c, { duration_s: s.duration_s, has_audio: s.has_audio, proposed_in_s: mid - 1, proposed_out_s: mid + 1, low_fps_lead_in_s: Math.min(c.low_fps_lead_in_s, mid - 1) });
  });
  fs.writeFileSync(out, JSON.stringify(r, null, 2));
' "$style" "$request" "${facts[@]}"

parts=(-F "request=@$request;type=application/json")
i=0
for id in $(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1])).clips.map((c) => c.moment_id).join(" "))' "$request"); do
  parts+=(-F "$id.mp4=@${samples[$((i % ${#samples[@]}))]};type=video/mp4")
  i=$((i + 1))
done

auth=(-H "Authorization: Bearer $token")
start=$(date +%s)
job=$(curl -fsS "${auth[@]}" "${parts[@]}" "$base/v1/agent" | node -e 'process.stdin.on("data", (d) => console.log(JSON.parse(d).job_id))')
echo "job $job ($style, ${#samples[@]} sample clips for $i moments)"

while :; do
  status=$(curl -fsS "${auth[@]}" "$base/v1/agent/$job")
  state=$(node -e 'const j = JSON.parse(process.argv[1]); console.log(`${j.status} ${Math.round(j.progress * 100)}`)' "$status")
  printf '\r  %s%% after %ss ' "$state" "$(($(date +%s) - start))"
  case "$state" in
    completed*) echo; break ;;
    failed*) echo; echo "FAIL $style: $status"; exit 1 ;;
  esac
  sleep 5
done

curl -fsS "${auth[@]}" -o "$result" "$base/v1/agent/$job/result"
curl -fsS "${auth[@]}" -o "$video" "$base/v1/agent/$job/video"
elapsed=$(($(date +%s) - start))

IFS=, read -r width height rate < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 "$video")
duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video")
node -e '
  const [style, request, result, w, h, rate, dur] = process.argv.slice(1);
  const fs = require("fs");
  const preset = JSON.parse(fs.readFileSync("../contracts/style_presets.json")).presets[style].output;
  const target = JSON.parse(fs.readFileSync(request)).effective_target_s;
  const r = JSON.parse(fs.readFileSync(result));
  const [n, d] = rate.split("/").map(Number);
  const errors = [];
  if (+w !== preset.width || +h !== preset.height) errors.push(`size ${w}x${h}, want ${preset.width}x${preset.height}`);
  if (Math.abs(n / d - preset.fps) > 0.01) errors.push(`fps ${rate}, want ${preset.fps}`);
  if (Math.abs(+dur - r.total_s) > 0.5) errors.push(`duration ${dur} s, result says ${r.total_s} s`);
  if (Math.abs(r.total_s - target) > 0.1 * target) errors.push(`total_s ${r.total_s} outside ±10% of ${target}`);
  console.log(`${errors.length ? "FAIL" : "ok  "} ${style}: ${w}x${h} ${rate} fps, ${(+dur).toFixed(3)} s (result ${r.total_s} s, target ${target} s), title "${r.title.text}", ${r.moments.length} moments: ${r.moments.map((m) => m.moment_id).join(" ")}${errors.length ? ": " + errors.join("; ") : ""}`);
  process.exit(errors.length ? 1 : 0);
' "$style" "$request" "$result" "$width" "$height" "$rate" "$duration"
echo "     done in ${elapsed}s -> $video (the server log has turns, renders and cost)"
