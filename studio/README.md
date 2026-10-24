# Roamory Studio (Mac bridge)

The iPhone app sends a trip's saved clips here over the local Wi-Fi, and Claude Code on this Mac edits them into a highlight video with FFmpeg. TRD §9; API in `contracts/README.md` ("/v1/studio").

## Setup

1. `brew install ffmpeg` and Xcode command-line tools (the title cards are drawn by `card.swift`).
2. Log in to Claude Code on this Mac (`claude`, then `/login`). The edit runs on that account.
3. `uv venv studio/.venv --python 3.13 && uv pip install --python studio/.venv/bin/python -r studio/requirements.txt`

## Run

From the repo root: `studio/.venv/bin/python -m studio.server`. It prints a 6-digit pairing code and advertises itself as "Roamory Studio on <Mac>" (`dns-sd -B _roamory._tcp` shows it).

On the iPhone, on the same Wi-Fi: open the camera screen, tap the film button, pick the Mac, enter the code once, and tap **Make video**. The video lands in Photos. Settings are in `config.toml` (model, turn and budget limits, timeout).

## How a job runs

`job.py` makes `studio/.jobs/<job_id>/` with `clips/`, `brief.json` (style preset, trip context, effective target, title), `cards/` (title and end card PNGs) and empty `frames/`, `work/`, `out/`. Then it runs:

```
claude -p <prompt.md> --model … --max-turns … --max-budget-usd … --output-format stream-json --verbose
  --no-session-persistence --restricted --strict-mcp-config
  --tools Read Write Edit Glob Bash --allowedTools Read Write Edit Glob "Bash(ffmpeg:*)" "Bash(ffprobe:*)"
  --permission-mode dontAsk
```

Claude watches the clips through extracted frames, plans in `out/plan.md`, renders `out/video.mp4` and writes `out/result.json`. The bridge checks the result (`rules.py`) before the phone can download it, and deletes the workspace after the download or after `job_ttl_min`.

`--restricted` confines the file tools to the workspace and ignores user settings, but `ffmpeg` itself can write anywhere this Mac user can. That is fine on a dev Mac; don't run the bridge on a shared machine.

## Test

- `cd studio && .venv/bin/python -m pytest` (a fake `claude` stands in; needs ffmpeg).
- With the server running: `studio/.venv/bin/python studio/scripts/smoke.py [style] [clip.mp4 …]` runs real Claude on the RoamoryKit sample clips (or yours) and writes `studio/.jobs/smoke_<style>.mp4`. It spends Claude usage.
