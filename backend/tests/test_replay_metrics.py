from tools.replay_eval import frame_times, score_run


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
