Turn the raw video clips in `clips/` into a polished video with text, animations, and music using FFmpeg. Compose the music yourself and time the cuts to the music's beat. Make the visuals and audio as stunning as possible.

First read:
- `brief.json`: the style and its preset (output size and fps), the trip context, the title, `effective_target_s` (the video's length, within ±10 %), `max_renders` (the most full-length encodes you may do) and every clip, oldest first. `recorded_at` is UTC, so do not show clock times; `length_hours` is the planned filming time in hours.
- `style.md`: the creative direction for this style. It is guidance, not a limit.
- `tools.md`: how to draw text with `roamory-text` (this ffmpeg has no `drawtext`) and compose music with `roamory-music`.
- `cards/`: ready-made title (`title.png`, `title_overlay.png`) and end (`end.png`) cards you may use or replace.

Watch the clips by extracting frames into `frames/<clip_id>/` and reading them.

Constraints:
- Work only in this directory and write only into `frames/`, `work/` and `out/` (the tools cannot create folders). In Bash use only `ffmpeg`, `ffprobe`, `roamory-text` and `roamory-music`.
- Before each step write one short line starting with `STAGE:` (for example `STAGE: Composing the music`); the traveler sees it, so never mention Claude in it.
- Write `out/video.mp4` (H.264 yuv420p, AAC 48 kHz, `-movflags +faststart`, the preset's size and fps) and `out/result.json`:
  ```json
  {"total_s": 49.8, "title": {"text": "...", "subtitle": "..."},
   "moments": [{"clip_id": "c_01", "start_s": 2.5, "end_s": 8.4}]}
  ```
  `total_s` is the duration ffprobe reports for the video, `title` is copied from `brief.json`, and `moments` has one entry per clip in playback order with the seconds it is on screen.

Check the finished video with ffprobe and frame grabs, fix anything wrong, then reply with one line summarising the cut.
