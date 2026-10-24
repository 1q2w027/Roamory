import json

import httpx

from tests.conftest import load_example
from tools.replay_eval import evaluate_one, frame_times, new_trip_id, score_run


def test_score_run():
    m = score_run([(0, False), (20_000, True), (60_000, True), (90_000, False)],
                  should_save_ms=[22_000, 120_000], tolerance_ms=10_000)
    assert m == {"precision": 0.5, "recall": 0.5, "kept": 2, "calls": 4}


def test_score_run_nothing_kept():
    assert score_run([(0, False)], [5_000], 10_000)["precision"] == 1.0


def test_frame_times_from_ffmpeg_names(tmp_path):
    for n in (1, 2, 10):
        (tmp_path / f"{n:05d}.jpg").write_bytes(b"x")
    assert [t for t, _ in frame_times(tmp_path)] == [0, 2_000, 18_000]


def _client(status: int, body: str) -> httpx.Client:
    return httpx.Client(base_url="http://test", transport=httpx.MockTransport(lambda req: httpx.Response(status, text=body)))


def test_errors_are_not_counted_as_skips(tmp_path):
    frames = []
    for n in (1, 2, 3):
        path = tmp_path / f"{n:05d}.jpg"
        path.write_bytes(b"\xff\xd8\xff")
        frames.append(((n - 1) * 2000, path))
    ctx = {"sample_t_ms": 4000}
    assert evaluate_one(_client(429, '{"code":"rate_limited"}'), "tok", ctx, frames) is None
    assert evaluate_one(_client(502, "<html>bad gateway</html>"), "tok", ctx, frames) is None  # non-JSON body
    body = load_example("evaluation_save.json")
    assert evaluate_one(_client(200, json.dumps(body)), "tok", ctx, frames) == body


def test_each_run_gets_its_own_trip_id():
    assert new_trip_id() != new_trip_id()
    assert new_trip_id().startswith("t_replay_")
