# Roamory Studio (Mac bridge)

The iPhone app sends a trip's saved clips here over the local Wi-Fi, and Claude Code on this Mac edits them into a highlight video with FFmpeg. TRD §9; API in `contracts/README.md` ("/v1/studio").

## Setup

1. `brew install ffmpeg` and Xcode command-line tools (the Swift helpers below are compiled on first use).
2. Log in to Claude Code on this Mac (`claude`, then `/login`). The edit runs on that account.
3. `uv venv studio/.venv --python 3.13 && uv pip install --python studio/.venv/bin/python -r studio/requirements.txt`

## Run

From the repo root: `studio/.venv/bin/python -m studio.server`. It prints a 6-digit pairing code and advertises itself as "Roamory Studio on <Mac>" (`dns-sd -B _roamory._tcp` shows it).

On the iPhone, on the same Wi-Fi: open the camera screen, tap the film button, pick the Mac, enter the code once, and tap **Make video**. The video lands in Photos. Settings are in `config.toml` (model, turn and budget limits, timeout).

## How a job runs

`job.py` makes `studio/.jobs/<job_id>/` with `clips/`, `brief.json` (style preset, trip context, effective target, title), `style.md` (the style's creative direction from `styles/`), `cards/` (default title and end card PNGs) and empty `frames/`, `work/`, `out/`. Then it runs:

```
claude -p <prompt.md> --model … --max-turns … --max-budget-usd … --output-format stream-json --verbose
  --no-session-persistence --restricted --strict-mcp-config
  --tools Read Write Edit Glob Bash --allowedTools Read Write Edit Glob "Bash(ffmpeg:*)" "Bash(ffprobe:*)"
  "Bash(roamory-text:*)" "Bash(roamory-music:*)" --permission-mode dontAsk
```

Claude reads `brief.json`, `style.md` and `tools.md`, watches the clips through extracted frames, draws its text and composes its music with the helpers, renders `out/video.mp4` and writes `out/result.json`. The style preset and `styles/<style>.md` are guidance: Claude picks any transitions, effects, text and music that suit the footage.

At `/start`, `eta.py` estimates how long the edit will take from the number of clips, their footage length and upload size, the output length times `max_renders`, and the model (`eta_*` in `config.toml`). It then scales that guess by the median of actual / guess over the last 10 finished runs with the same model, kept in `state_dir/eta_history.jsonl`. The job status reports the seconds left as `eta_s`, and the phone shows it.

The helpers are compiled into `studio/.jobs/_bin/` (outside every workspace, on Claude's `PATH`), each again when its source changes. Their spec formats are documented in `tools.md`, which is copied into every workspace.

- `card.swift`: the default title and end cards, drawn before the run.
- `text.swift` (`roamory-text <spec.json>`): text and shape layers in any installed font to transparent PNGs, because Homebrew's ffmpeg has no `drawtext`. `--fonts` lists the fonts.
- `music.swift` (`roamory-music <score.json>`): renders a score Claude writes (tempo, tracks of notes, 26 synthesised instruments and drums, envelopes, filters, pan, reverb) to a 48 kHz stereo WAV. No music files are used. The bridge checks the result (`rules.py`) before the phone can download it, and deletes the workspace after the download or after `job_ttl_min`.

`--restricted` confines the file tools to the workspace and ignores user settings, but `ffmpeg` itself can write anywhere this Mac user can. That is fine on a dev Mac; don't run the bridge on a shared machine.

## Test

- `cd studio && .venv/bin/python -m pytest` (a fake `claude` stands in; needs ffmpeg).
- With the server running: `studio/.venv/bin/python studio/scripts/smoke.py [style] [clip.mp4 …]` runs real Claude on the RoamoryKit sample clips (or yours) and writes `studio/.jobs/smoke_<style>.mp4`. It spends Claude usage.
