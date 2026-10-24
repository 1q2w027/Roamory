"""Replay a recorded walk through a running backend's POST /v1/evaluate and score the decisions.

Usage: python tools/replay_eval.py DIR --token $APP_TOKEN [--server URL] [--style cinematic]
       [--trip-type honeymoon] [--country Japan] [--city Kyoto] [--every-s 10]

DIR/frames/NNNNN.jpg come from `ffmpeg -i walk.mp4 -vf "fps=0.5,scale=512:-2" frames/%05d.jpg`, so frame n
is at (n - 1) * 2000 ms. DIR/labels.json is {"should_save_ms": [...], "tolerance_ms": 10000}.
This skips the phone's Stage 1 gate (it sends a sample every --every-s); use it to tune the prompt.
Requests go out back to back, faster than a real trip, so start the server with the trip budget raised:
  BUCKET_CAPACITY=1000 FAST_PER_HOUR=10000 STRONG_PER_HOUR=1000 .venv/bin/uvicorn app.main:app
Each run uses a fresh trip_id, and error responses are reported separately, never counted as skips.
"""
import argparse
import json
import statistics
import sys
import uuid
from collections import Counter
from pathlib import Path

import httpx

SAMPLE_MS = 2000


def frame_times(frames_dir: Path) -> list[tuple[int, Path]]:
    """(t_ms, path) for ffmpeg's 1-based numbered frames, in time order."""
    paths = sorted(frames_dir.glob("*.jpg"), key=lambda p: int(p.stem))
    return [((int(p.stem) - 1) * SAMPLE_MS, p) for p in paths]


def score_run(decisions: list[tuple[int, bool]], should_save_ms: list[int], tolerance_ms: int) -> dict:
    """A label is hit when a kept decision lies within tolerance; precision counts kept decisions near any label."""
    kept = [t for t, keep in decisions if keep]
    near = lambda t, targets: any(abs(t - x) <= tolerance_ms for x in targets)  # noqa: E731
    return {
        "precision": sum(near(t, should_save_ms) for t in kept) / len(kept) if kept else 1.0,
        "recall": sum(near(x, kept) for x in should_save_ms) / len(should_save_ms) if should_save_ms else 1.0,
        "kept": len(kept),
        "calls": len(decisions),
    }


def new_trip_id() -> str:
    return f"t_replay_{uuid.uuid4().hex[:8]}"


def evaluate_one(client: httpx.Client, token: str, ctx: dict, triple: list[tuple[int, Path]]) -> dict | None:
    """POST one sample; the evaluation body, or None (printed) when the server answers with an error."""
    files = [("context", ("context.json", json.dumps(ctx), "application/json"))]
    files += [(f"frame_{k}.jpg", (f"frame_{k}.jpg", path.read_bytes(), "image/jpeg")) for k, (_, path) in enumerate(triple)]
    r = client.post("/v1/evaluate", files=files, headers={"Authorization": f"Bearer {token}"})
    if r.status_code != 200:
        try:
            code = r.json().get("code")
        except ValueError:
            code = r.text[:80]
        print(f"{ctx['sample_t_ms'] / 1000:7.1f}s  error {r.status_code} {code}")
        return None
    return r.json()


def context(args: argparse.Namespace, trip_id: str, t_ms: int, recent: list[str]) -> dict:
    return {
        "version": 1,
        "trip_id": trip_id,
        "install_id": "i_replay",
        "purpose": "select",
        "sample_t_ms": t_ms,
        "style": args.style,
        "trip_type": args.trip_type,
        "destination": {"continent": None, "country": args.country, "city": args.city},
        "length_days": 1,
        "local": {"score": 0.6, "novelty": 0.5, "sharpness": 150.0, "change": 10.0, "motion": 10.0, "forced": False},
        "recent_descriptions": recent[:5],
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dir", type=Path)
    p.add_argument("--server", default="http://localhost:8000")
    p.add_argument("--token", required=True)
    p.add_argument("--style", default="cinematic")
    p.add_argument("--trip-type", default="honeymoon")
    p.add_argument("--country", default="Japan")
    p.add_argument("--city", default="Kyoto")
    p.add_argument("--every-s", type=int, default=10)
    args = p.parse_args()

    labels = json.loads((args.dir / "labels.json").read_text())
    frames = frame_times(args.dir / "frames")
    step = max(args.every_s * 1000 // SAMPLE_MS, 1)
    decisions: list[tuple[int, bool]] = []
    tiers: Counter[str] = Counter()
    latencies: list[int] = []
    recent: list[str] = []

    trip_id = new_trip_id()
    errors = 0
    with httpx.Client(base_url=args.server, timeout=10.0) as client:
        for i in range(2, len(frames), step):  # the triple ending at frame i
            t_ms = frames[i][0]
            body = evaluate_one(client, args.token, context(args, trip_id, t_ms, recent), frames[i - 2 : i + 1])
            if body is None:
                errors += 1
                continue
            decisions.append((t_ms, body["keep"]))
            tiers[body["tier"]] += 1
            latencies.append(body["latency_ms"])
            if body["keep"]:
                recent.insert(0, body["verdict"]["description"])
            print(f"{t_ms / 1000:7.1f}s  {'KEEP' if body['keep'] else 'skip'}  s2={body['s2']:.2f} "
                  f"{body['tier']}  {body['verdict']['description']}")

    m = score_run(decisions, labels["should_save_ms"], labels.get("tolerance_ms", 10_000))
    print(f"\nprecision {m['precision']:.2f}  recall {m['recall']:.2f}  kept {m['kept']}/{m['calls']}  errors {errors}")
    if latencies:
        print(f"tiers {dict(tiers)}  mean latency {statistics.mean(latencies):.0f} ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
