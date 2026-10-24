"""Per-trip call budget for POST /v1/evaluate (TRD 8.3), in memory (TRD 2)."""
import time
from collections import defaultdict, deque
from collections.abc import Callable
from dataclasses import dataclass, field

from app.config import Settings
from app.errors import AppError

# TRD 8.3 caps calls per recording hour. The server can't see pauses, so it uses a rolling wall-clock hour.
WINDOW_S = 3600.0


@dataclass
class _Trip:
    tokens: float
    refilled_at: float
    fast: deque[float] = field(default_factory=deque)
    describe: deque[float] = field(default_factory=deque)


def _in_window(calls: deque[float], now: float) -> int:
    while calls and calls[0] <= now - WINDOW_S:
        calls.popleft()
    return len(calls)


class BudgetBook:
    def __init__(self, settings: Settings, now: Callable[[], float] = time.monotonic):
        self.s = settings
        self.now = now
        self._trips: defaultdict[str, _Trip] = defaultdict(lambda: _Trip(settings.BUCKET_CAPACITY, now()))

    def _trip(self, trip_id: str, now: float) -> _Trip:
        t = self._trips[trip_id]
        t.tokens = min(self.s.BUCKET_CAPACITY, t.tokens + (now - t.refilled_at) / self.s.BUCKET_REFILL_S)
        t.refilled_at = now
        return t

    def take_select(self, trip_id: str) -> None:
        """One token from the trip's bucket and one fast call, or 429 with nothing spent."""
        now = self.now()
        t = self._trip(trip_id, now)
        if t.tokens < 1:
            raise AppError(429, "rate_limited", "trip evaluate budget is empty; try again later")
        if _in_window(t.fast, now) >= self.s.FAST_PER_HOUR:
            raise AppError(429, "rate_limited", f"over {self.s.FAST_PER_HOUR} evaluations per hour for this trip")
        t.tokens -= 1
        t.fast.append(now)

    def take_describe(self, trip_id: str) -> None:
        now = self.now()
        t = self._trip(trip_id, now)
        if _in_window(t.describe, now) >= self.s.DESCRIBE_PER_HOUR:
            raise AppError(429, "rate_limited", f"over {self.s.DESCRIBE_PER_HOUR} button descriptions per hour")
        t.describe.append(now)
