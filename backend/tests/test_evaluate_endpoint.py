import json
import logging

from jsonschema import Draft202012Validator

from app.config import REPO_ROOT
from tests.conftest import JPEG, evaluate_multipart, load_example, ok

SELECT = load_example("evaluate_context_select.json")
DESCRIBE = load_example("evaluate_context_describe.json")
CONFIDENT = dict(preference_alignment=0.9, visual_interest=0.9, significance=0.9, visual_quality=0.9)
EVALUATION_SCHEMA = json.loads((REPO_ROOT / "contracts" / "evaluation.schema.json").read_text())


def test_select_happy_path(client, fake_model):
    fake_model.responses = [ok(**CONFIDENT)]
    r = client.post("/v1/evaluate", **evaluate_multipart(SELECT))
    assert r.status_code == 200
    Draft202012Validator(EVALUATION_SCHEMA).validate(r.json())
    assert r.json()["keep"] is True


def test_requires_token(client):
    kw = evaluate_multipart(SELECT)
    kw["headers"] = {}
    r = client.post("/v1/evaluate", **kw)
    assert r.status_code == 401 and r.json()["code"] == "unauthorized"


def test_one_frame_accepted(client, fake_model):
    fake_model.responses = [ok(**CONFIDENT)]
    r = client.post("/v1/evaluate", **evaluate_multipart(SELECT, n_frames=1))
    assert r.status_code == 200
    assert r.json()["verdict"]["best_frame_index"] == 0  # clamped to the one frame sent


def test_frame_gap_rejected(client, fake_model):
    r = client.post("/v1/evaluate", **evaluate_multipart(SELECT, names=["frame_0.jpg", "frame_2.jpg"]))
    assert r.status_code == 400 and r.json()["code"] == "bad_request"
    assert fake_model.calls == []


def test_too_many_or_no_frames_rejected(client):
    assert client.post("/v1/evaluate", **evaluate_multipart(SELECT, n_frames=4)).status_code == 400
    assert client.post("/v1/evaluate", **evaluate_multipart(SELECT, n_frames=0)).status_code == 400


def test_missing_context_rejected(client):
    kw = evaluate_multipart(SELECT)
    kw["files"] = kw["files"][1:]
    assert client.post("/v1/evaluate", **kw).status_code == 400


def test_invalid_request_spends_no_budget(client, fake_model):
    for bad in [
        evaluate_multipart(SELECT, frame=b"\x89PNG fake"),
        evaluate_multipart(SELECT, frame=JPEG + b"0" * 400_001),
        evaluate_multipart(SELECT | {"purpose": "spy"}),
    ]:
        assert client.post("/v1/evaluate", **bad).status_code == 400
    assert fake_model.calls == []
    fake_model.responses = [ok()] * 10  # each escalates: 2 calls per request
    assert all(client.post("/v1/evaluate", **evaluate_multipart(SELECT)).status_code == 200 for _ in range(5))


def test_describe_ignores_empty_select_bucket(client, fake_model):
    fake_model.responses = [ok(**CONFIDENT)] * 5
    for _ in range(5):
        assert client.post("/v1/evaluate", **evaluate_multipart(SELECT)).status_code == 200
    r = client.post("/v1/evaluate", **evaluate_multipart(SELECT))
    assert r.status_code == 429 and r.json()["code"] == "rate_limited"
    fake_model.responses = [ok(save_decision="skip", preference_alignment=0.0)]
    r = client.post("/v1/evaluate", **evaluate_multipart(DESCRIBE))
    assert r.status_code == 200 and r.json()["keep"] is True


def test_logs_hold_no_frames(client, fake_model, caplog):
    caplog.set_level(logging.DEBUG)
    fake_model.responses = [ok(**CONFIDENT)]
    client.post("/v1/evaluate", **evaluate_multipart(SELECT))
    assert "evaluate trip=t_123" in caplog.text
    assert "/9j/" not in caplog.text and "temple gate" not in caplog.text  # base64 JPEG prefix, description
