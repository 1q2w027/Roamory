# Roamory Studio (Mac bridge)

The iPhone app sends a trip's saved clips here over the local Wi-Fi, and Claude Code on this Mac edits them into a highlight video with FFmpeg. TRD §9; API in `contracts/README.md` ("/v1/studio").

## Setup

1. `brew install ffmpeg`.
2. Log in to Claude Code on this Mac (`claude`, then `/login`). The edit runs on that account.
3. `uv venv studio/.venv --python 3.13 && uv pip install --python studio/.venv/bin/python -r studio/requirements.txt`

## Run

From the repo root: `studio/.venv/bin/python -m studio.server`. It prints a 6-digit pairing code and advertises itself as "Roamory Studio on <Mac>" (`dns-sd -B _roamory._tcp` shows it).

On the iPhone, on the same Wi-Fi: open the camera screen, tap the film button, pick the Mac, enter the code once, and tap **Make video**. The video lands in Photos. Settings are in `config.toml` (model, turn and budget limits, timeout).

## How a job runs

`job.py` makes `studio/.jobs/<job_id>/` with `clips/`, `brief.json` (facts about the trip and its clips, plus the requirements: output size and fps, target length, render budget; no title or other text chosen in advance), `style.md` (the style's creative direction from `styles/`) and empty `frames/`, `work/`, `out/`. Then it runs:

```
claude -p <prompt.md> --model … --max-turns … --max-budget-usd … --output-format stream-json --verbose
  --no-session-persistence --permission-mode bypassPermissions
```

Claude reads `brief.json` and `style.md`, watches the clips through extracted frames, makes its own text, title and end cards and music, renders `out/video.mp4` and writes `out/result.json`. The style preset and `styles/<style>.md` are guidance: Claude picks any transitions, effects, text and music that suit the footage.

At `/start`, `eta.py` estimates how long the edit will take from the number of clips, their footage length and upload size, the output length times `max_renders`, and the model (`eta_*` in `config.toml`). It then scales that guess by the median of actual / guess over the last 10 finished runs with the same model, kept in `state_dir/eta_history.jsonl`. The job status reports the seconds left as `eta_s`, and the phone shows it.

The bridge checks the result (`rules.py`) before the phone can download it, and deletes the workspace after the download or after `job_ttl_min`.

Claude runs with every tool, your user and project settings and your MCP servers, and without permission prompts, in the job's workspace as its working directory. It can read, write and run anything this Mac user can. That is fine on a dev Mac; don't run the bridge on a shared machine.

## Test

- `cd studio && .venv/bin/python -m pytest` (a fake `claude` stands in; needs ffmpeg).
- With the server running: `studio/.venv/bin/python studio/scripts/smoke.py [style] [clip.mp4 …]` runs real Claude on the RoamoryKit sample clips (or yours) and writes `studio/.jobs/smoke_<style>.mp4`. It spends Claude usage.
