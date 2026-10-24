#!/usr/bin/env python3
"""Stands in for `claude -p` in tests. FAKE_MODE: ok (renders a test video and a valid result), short (result
that misses the target), fail (exits with nothing written), hang (sleeps past any test timeout)."""
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
total = brief["effective_target_s"] * (0.5 if mode == "short" else 1)
w, h = brief["preset"]["output"]["width"] // 4, brief["preset"]["output"]["height"] // 4
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc=size={w}x{h}:rate=30:duration={total}",
                "-pix_fmt", "yuv420p", "out/video.mp4"], check=True)
slot = (total - 2) / len(brief["clips"])
moments = [{"clip_id": c["clip_id"], "start_s": 1 + k * slot, "end_s": 1 + (k + 1) * slot}
           for k, c in enumerate(brief["clips"])]
Path("out/result.json").write_text(json.dumps({"total_s": total, "title": brief["title"], "moments": moments}))
emit({"type": "result", "subtype": "success", "num_turns": 3, "total_cost_usd": 0})
