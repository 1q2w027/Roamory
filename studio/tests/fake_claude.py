#!/usr/bin/env python3
"""Stands in for `claude -p` in tests. FAKE_MODE: ok (renders a test video and a valid result), reuse (a valid result
that leaves out the last clip and shows the first twice), short (result that misses the target), fail (exits with
nothing written), hang (sleeps past any test timeout)."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

mode = os.environ.get("FAKE_MODE", "ok")
brief = json.loads(Path("brief.json").read_text())


def emit(event):
    print(json.dumps(event), flush=True)


emit({"type": "assistant", "message": {"content": [{"type": "text", "text": "STAGE: Watching clips"}]}})
if mode == "hang":
    time.sleep(60)
if mode == "fail":
    sys.exit(1)
if mode in ("ok", "reuse"):
    assert Path("style.md").read_text().startswith("# ")
total = brief["requirements"]["target_s"] * (0.5 if mode == "short" else 1)
w, h = brief["requirements"]["width"] // 4, brief["requirements"]["height"] // 4
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc=size={w}x{h}:rate=30:duration={total}",
                "-pix_fmt", "yuv420p", "out/video.mp4"], check=True)
shown = brief["clips"][:-1] + brief["clips"][:1] if mode == "reuse" else brief["clips"]
slot = (total - 2) / len(shown)
moments = [{"clip_id": c["clip_id"], "start_s": 1 + k * slot, "end_s": 1 + (k + 1) * slot}
           for k, c in enumerate(shown)]
Path("out/result.json").write_text(json.dumps({"total_s": total, "title": {"text": "Test", "subtitle": None}, "moments": moments}))
emit({"type": "result", "subtype": "success", "num_turns": 3, "total_cost_usd": 0})
