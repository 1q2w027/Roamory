"""Sends clips to a running bridge and downloads the video Claude makes. Uses real Claude Code: it spends usage, so
run it by hand, never in the tests.

Usage: studio/.venv/bin/python studio/scripts/smoke.py [style] [clip.mp4 ...]
Defaults to reels and the sample clips bundled with RoamoryKit. Writes the video next to this repo's studio/.jobs/.
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = "http://127.0.0.1:8787"
TOKEN = (Path.home() / ".roamory-studio" / "token").read_text().strip()


def call(method, path, body=None, data=None):
    headers = {"Authorization": f"Bearer {TOKEN}"}
    if body is not None:
        data, headers["Content-Type"] = json.dumps(body).encode(), "application/json"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
            return json.loads(raw) if r.headers.get("Content-Type") == "application/json" else raw
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: {e.code} {e.read().decode()}")


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type", "-of", "json",
                          str(path)], capture_output=True, text=True, check=True).stdout
    info = json.loads(out)
    return float(info["format"]["duration"]), any(s["codec_type"] == "audio" for s in info["streams"])


def main():
    style = sys.argv[1] if len(sys.argv) > 1 else "reels"
    files = [Path(p) for p in sys.argv[2:]] or sorted(
        (ROOT / "ios/RoamoryKit/Sources/RoamoryKit/Resources/SampleClips").glob("*.mp4"))
    start = datetime(2026, 10, 20, 9, tzinfo=timezone.utc)
    clips = []
    for k, f in enumerate(files):
        duration, has_audio = probe(f)
        clips.append({"clip_id": f"c_{k + 1:02d}", "recorded_at": (start + timedelta(hours=k)).isoformat(),
                      "duration_s": round(duration, 3), "has_audio": has_audio})
    request = {"trip_id": "t_smoke", "style": style, "clips": clips,
               "context": {"destination": {"country": "Japan", "city": "Kyoto"}, "trip_type": "City break",
                           "start_date": "2026-10-20"}}
    job_id = call("POST", "/v1/studio/jobs", request)["job_id"]
    for c, f in zip(clips, files):
        call("PUT", f"/v1/studio/jobs/{job_id}/clips/{c['clip_id']}.mp4", data=f.read_bytes())
    call("POST", f"/v1/studio/jobs/{job_id}/start")
    print(f"job {job_id} started ({style}, {len(clips)} clips)")
    last = None
    while True:
        job = call("GET", f"/v1/studio/jobs/{job_id}")
        if job["stage"] != last:
            print(f"  {job['elapsed_s']:6.0f} s  {job['stage']}")
            last = job["stage"]
        if job["status"] == "failed":
            sys.exit(f"failed: {job['error']}")
        if job["status"] == "completed":
            break
        time.sleep(2)
    result = call("GET", f"/v1/studio/jobs/{job_id}/result")
    print(json.dumps(result, indent=2))
    out = ROOT / "studio" / ".jobs" / f"smoke_{style}.mp4"
    out.write_bytes(call("GET", f"/v1/studio/jobs/{job_id}/video"))
    print(f"video: {out} ({probe(out)[0]:.2f} s, {job['elapsed_s']:.0f} s to make)")


if __name__ == "__main__":
    main()
