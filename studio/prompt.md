Turn the raw video clips in `clips/` into a polished video with text, animations, and music using FFmpeg. Compose the music yourself and time the cuts to the music's beat. Make the visuals and audio as stunning as possible.

First read:
- `brief.json`: facts about the trip and its footage. `trip` is what the traveler told the app (destination, trip type, start date, `length_hours` of planned filming); `footage` and `clips` (oldest first) describe what was saved. `recorded_at` is UTC, so do not show clock times. Use these facts however you like, or not at all: they are background, not text to put on screen. Only `requirements` binds you: the output `width`, `height` and `fps`, `target_s` (the video's length, within ±10 %) and `max_renders` (the most full-length encodes you may do).
- `style.md`: the creative direction for this style. It is guidance, not a limit.

Watch the clips by extracting frames into `frames/<clip_id>/` and reading them.

Make all the text and the music yourself. Decide from what the clips show how the video opens and ends, what it is called and what (if anything) it says on screen; a city name over a trip type is the least interesting choice, so only use it when nothing better fits. Every video should feel made for its own footage. This Mac's ffmpeg has no `drawtext`, so find another way to draw text.

Constraints:
- Work only in this directory and write only into `frames/`, `work/` and `out/`.
- Before each step write one short line starting with `STAGE:` (for example `STAGE: Composing the music`); the traveler sees it, so never mention Claude in it.
- Write `out/video.mp4` (H.264 yuv420p, AAC 48 kHz, `-movflags +faststart`, the size and fps in `requirements`) and `out/result.json`:
  ```json
  {"total_s": 49.8, "title": {"text": "...", "subtitle": "..."},
   "moments": [{"clip_id": "c_01", "start_s": 2.5, "end_s": 8.4}]}
  ```
  `total_s` is the duration ffprobe reports for the video, `title` is the name you gave the video (`text` up to 40 characters, `subtitle` up to 60 or null), whether or not it appears on screen, and `moments` has one entry per clip in playback order with the seconds it is on screen.

Check the finished video with ffprobe and frame grabs, fix anything wrong, then reply with one line summarising the cut.
