import json
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from studio import eta, rules
from studio.config import CONTRACTS, Config
from studio.job import STYLES, claude_command, stage_from_event, title_for
from studio.server import make_server

FAKE = str(Path(__file__).parent / "fake_claude.py")


def example(style="reels"):
    return json.loads((CONTRACTS / "examples" / f"studio_request_{style}.json").read_text())


@pytest.fixture
def bridge(tmp_path, monkeypatch):
    config = Config(claude=FAKE, timeout_s=20, state_dir=str(tmp_path / "state"), jobs_dir=str(tmp_path / "jobs"))
    server = make_server(config, port=0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"

    def call(method, path, body=None, data=None, token=server.studio.token):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(base + path, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if r.headers.get("Content-Type") == "application/json" else raw)
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    call.studio = server.studio
    call.monkeypatch = monkeypatch
    yield call
    server.shutdown()


def upload_all(call, request):
    status, body = call("POST", "/v1/studio/jobs", request)
    assert status == 201, body
    job_id = body["job_id"]
    for c in request["clips"]:
        assert call("PUT", f"/v1/studio/jobs/{job_id}/clips/{c['clip_id']}.mp4", data=b"not really mp4")[0] == 204
    return job_id


def wait(call, job_id):
    for _ in range(200):
        status, job = call("GET", f"/v1/studio/jobs/{job_id}")
        if job["status"] in ("completed", "failed"):
            return job
        time.sleep(0.1)
    raise AssertionError("job did not finish")


def test_pair(bridge):
    assert bridge("POST", "/v1/studio/pair", {"code": "nope"}, token=None)[0] == 401
    status, body = bridge("POST", "/v1/studio/pair", {"code": bridge.studio.code}, token=None)
    assert status == 200 and body["token"] == bridge.studio.token


def test_wrong_codes_rotate_the_code(bridge):
    first = bridge.studio.code
    for _ in range(5):
        bridge("POST", "/v1/studio/pair", {"code": "x"}, token=None)
    assert bridge.studio.code != first and bridge.studio.pair_failures == 0


def test_needs_token(bridge):
    assert bridge("POST", "/v1/studio/jobs", example(), token="wrong")[0] == 401


def test_rejects_bad_request(bridge):
    request = example()
    request["clips"].append(dict(request["clips"][0]))
    status, body = bridge("POST", "/v1/studio/jobs", request)
    assert status == 400 and "repeats" in body["message"]


def test_completes(bridge):
    bridge.monkeypatch.setenv("FAKE_MODE", "ok")
    job_id = upload_all(bridge, example())
    assert bridge("POST", f"/v1/studio/jobs/{job_id}/start")[0] == 202
    status, editing = bridge("GET", f"/v1/studio/jobs/{job_id}")
    rules._validator("studio_job.schema.json").validate(editing)
    job = wait(bridge, job_id)
    assert job["status"] == "completed" and job["eta_s"] is None, job
    rules._validator("studio_job.schema.json").validate(job)
    assert [json.loads(l)["model"] for l in (bridge.studio.config.state_path / eta.HISTORY_FILE).open()] == \
        [bridge.studio.config.model]
    status, result = bridge("GET", f"/v1/studio/jobs/{job_id}/result")
    assert status == 200 and [m["clip_id"] for m in result["moments"]] == ["c_01", "c_02", "c_03", "c_04"]
    status, video = bridge("GET", f"/v1/studio/jobs/{job_id}/video")
    assert status == 200 and len(video) > 1000
    assert bridge("GET", f"/v1/studio/jobs/{job_id}")[0] == 404


def test_start_needs_every_clip(bridge):
    status, body = bridge("POST", "/v1/studio/jobs", example())
    status, body = bridge("POST", f"/v1/studio/jobs/{body['job_id']}/start")
    assert status == 400 and "c_01" in body["message"]


def test_busy_while_a_job_is_active(bridge):
    bridge("POST", "/v1/studio/jobs", example())
    assert bridge("POST", "/v1/studio/jobs", example())[0] == 429


def test_completes_without_every_clip_once(bridge):
    bridge.monkeypatch.setenv("FAKE_MODE", "reuse")
    job_id = upload_all(bridge, example())
    bridge("POST", f"/v1/studio/jobs/{job_id}/start")
    assert wait(bridge, job_id)["status"] == "completed"


@pytest.mark.parametrize("mode", ["fail", "short"])
def test_fails(bridge, mode):
    bridge.monkeypatch.setenv("FAKE_MODE", mode)
    job_id = upload_all(bridge, example())
    bridge("POST", f"/v1/studio/jobs/{job_id}/start")
    job = wait(bridge, job_id)
    assert job["status"] == "failed" and job["error"]["code"] == "agent_failed"
    assert bridge("GET", f"/v1/studio/jobs/{job_id}/video")[0] == 404


def test_timeout(bridge):
    bridge.monkeypatch.setenv("FAKE_MODE", "hang")
    bridge.studio.config.timeout_s = 1
    job_id = upload_all(bridge, example())
    bridge("POST", f"/v1/studio/jobs/{job_id}/start")
    job = wait(bridge, job_id)
    assert job["error"]["code"] == "agent_timeout"


def test_effective_target():
    request = example("cinematic")
    assert rules.effective_target_s(request) == 50
    request["clips"] = [dict(request["clips"][0], duration_s=10)]
    assert rules.effective_target_s(request) == 14.5  # 10 s of footage + 2.5 title + 2 end card


def test_every_style_has_a_guide():
    for style in json.loads((CONTRACTS / "style_presets.json").read_text())["presets"]:
        assert (STYLES / f"{style}.md").exists()


def test_title_uses_only_the_context():
    assert title_for(example()) == {"text": "Kyoto", "subtitle": "City break · October 2026"}


def test_stage_parsing():
    text = {"type": "assistant", "message": {"content": [{"type": "text", "text": "ok\nSTAGE: Planning the edit"}]}}
    bash = {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Bash", "input": {"command": "ffmpeg ...", "description": "Render segment 3"}}]}}
    assert stage_from_event(text) == "Planning the edit"
    assert stage_from_event(bash) == "Render segment 3"
    assert stage_from_event({"type": "user"}) is None


def test_claude_is_not_confined():
    cmd = claude_command(Config(), "prompt")
    assert "bypassPermissions" in cmd
    assert not {"--restricted", "--strict-mcp-config", "--tools", "--allowedTools"} & set(cmd)


def test_estimate_grows_with_the_data_and_depends_on_the_model(tmp_path):
    config = Config(state_dir=str(tmp_path), model="claude-opus-5-5")
    request = example()
    guess, estimate = eta.estimate_s(config, request, 50 << 20)
    assert guess == estimate > config.eta_base_s
    assert eta.estimate_s(config, request, 500 << 20)[1] > estimate
    longer = example()
    longer["clips"] = longer["clips"] + [{**c, "clip_id": c["clip_id"] + "b"} for c in longer["clips"]]
    assert eta.estimate_s(config, longer, 50 << 20)[1] > estimate
    assert eta.estimate_s(Config(state_dir=str(tmp_path), model="claude-haiku-5-5"), request, 50 << 20)[1] < estimate
    config.timeout_s = 60
    assert eta.estimate_s(config, request, 50 << 20)[1] == 60


def test_estimate_learns_from_past_runs(tmp_path):
    config = Config(state_dir=str(tmp_path))
    guess, _ = eta.estimate_s(config, example(), 0)
    for actual in (1.8, 2.0, 2.2):
        eta.record(config, guess, guess * actual)
    eta.record(Config(state_dir=str(tmp_path), model="other"), guess, guess * 0.1)
    assert eta.scale(config) == pytest.approx(2.0)
    for _ in range(3):
        eta.record(config, guess, guess * 100)
    assert eta.scale(config) == eta.SCALE_LIMITS[1]


@pytest.mark.parametrize("hours", [1, 5, 24])
def test_accepts_and_preserves_length_hours(bridge, hours):
    request = example()
    request["context"]["length_hours"] = hours
    status, body = bridge("POST", "/v1/studio/jobs", request)
    assert status == 201, body
    assert bridge.studio.jobs[body["job_id"]].request["context"]["length_hours"] == hours


@pytest.mark.parametrize("hours", [0, 25, 1.5, "5", True, None])
def test_rejects_invalid_length_hours(bridge, hours):
    request = example()
    request["context"]["length_hours"] = hours
    status, body = bridge("POST", "/v1/studio/jobs", request)
    assert status == 400 and "length_hours" in body["message"]


def test_rejects_day_based_duration(bridge):
    request = example()
    request["context"]["length_days"] = request["context"].pop("length_hours")
    status, body = bridge("POST", "/v1/studio/jobs", request)
    assert status == 400 and "length_hours" in body["message"]
