"""Estimated time for one edit: a guess from the job's data and the model, scaled by how this Mac's past runs
compared with their guesses."""
import json
import statistics
import time
from pathlib import Path

from . import rules
from .config import Config

HISTORY_FILE = "eta_history.jsonl"
HISTORY_RUNS = 10
SCALE_LIMITS = (0.33, 3.0)


def model_factor(config: Config) -> float:
    """How long the model takes relative to the baseline: the first eta_model_factors key in its ID."""
    for key, factor in config.eta_model_factors.items():
        if key in config.model:
            return factor
    return 1.0


def guess_s(config: Config, request: dict, clip_bytes: int) -> float:
    """Claude watches each clip (frames scale with the footage), decodes the uploads and renders the output up to
    max_renders times, so the guess grows with each of those."""
    footage_s = sum(c["duration_s"] for c in request["clips"])
    work = (config.eta_base_s
            + config.eta_per_clip_s * len(request["clips"])
            + config.eta_per_footage_s * footage_s
            + config.eta_per_mb_s * clip_bytes / (1024 * 1024)
            + config.eta_per_output_s * rules.effective_target_s(request) * config.max_renders)
    return work * model_factor(config)


def _history(config: Config) -> Path:
    return config.state_path / HISTORY_FILE


def scale(config: Config) -> float:
    """Median of actual / guess over this model's last runs, 1 with none."""
    try:
        lines = _history(config).read_text().splitlines()
    except OSError:
        return 1.0
    ratios = []
    for line in lines:
        try:
            run = json.loads(line)
            if run["model"] == config.model and run["guess_s"] > 0:
                ratios.append(run["actual_s"] / run["guess_s"])
        except (ValueError, KeyError, TypeError):
            continue
    if not ratios:
        return 1.0
    low, high = SCALE_LIMITS
    return min(max(statistics.median(ratios[-HISTORY_RUNS:]), low), high)


def estimate_s(config: Config, request: dict, clip_bytes: int) -> tuple[float, float]:
    """(the unscaled guess, the estimate): the guess scaled by past runs, never past the timeout."""
    guess = guess_s(config, request, clip_bytes)
    return guess, min(guess * scale(config), config.timeout_s)


def record(config: Config, guess: float, actual_s: float):
    """Remembers a finished run so later estimates for this model learn from it."""
    run = {"model": config.model, "guess_s": round(guess, 1), "actual_s": round(actual_s, 1), "at": int(time.time())}
    with open(_history(config), "a") as f:
        f.write(json.dumps(run) + "\n")
