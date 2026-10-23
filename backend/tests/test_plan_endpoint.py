import copy

import anthropic
import httpx
import pytest

from tests.conftest import TOKEN, load_example, multipart, text_response, tool_response


@pytest.fixture
def reels_request():
    return load_example("plan_request_reels.json")


@pytest.fixture
def reels_spec():
    return load_example("edit_spec_reels.json")


def broken(spec: dict) -> dict:
    spec = copy.deepcopy(spec)
    spec["clips"] = [c for c in spec["clips"] if c["moment_id"] != "m_06"]
    return spec


def test_healthz_needs_no_auth(client):
    assert client.get("/healthz").json() == {"ok": True}


def test_valid_plan(client, fake_model, reels_request, reels_spec):
    fake_model.responses = [tool_response(reels_spec)]
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 200, r.text
    assert r.json() == reels_spec

    call = fake_model.calls[0]
    assert call["tool_choice"] == {"type": "auto"}
    images = [b for b in call["messages"][0]["content"] if b["type"] == "image"]
    assert len(images) == sum(c["thumbnail_count"] for c in reels_request["clips"])


def test_preset_fields_come_from_preset(client, fake_model, reels_request, reels_spec):
    spec = copy.deepcopy(reels_spec)
    spec["output"] = {"width": 640, "height": 480, "fps": 24}
    spec["music"]["track"] = "something_else"
    fake_model.responses = [tool_response(spec)]
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 200
    assert r.json()["output"] == {"width": 1080, "height": 1920, "fps": 30}
    assert r.json()["music"]["track"] == "reels_01"


def test_repair_retry_then_success(client, fake_model, reels_request, reels_spec):
    fake_model.responses = [tool_response(broken(reels_spec)), tool_response(reels_spec, "toolu_2")]
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 200
    assert len(fake_model.calls) == 2

    feedback = fake_model.calls[1]["messages"][-1]["content"][0]
    assert feedback["type"] == "tool_result"
    assert feedback["tool_use_id"] == "toolu_1"
    assert feedback["is_error"] is True
    assert "missing button moment m_06" in feedback["content"]


def test_invalid_twice_returns_422(client, fake_model, reels_request, reels_spec):
    fake_model.responses = [tool_response(broken(reels_spec)), tool_response(broken(reels_spec), "toolu_2")]
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 422
    body = r.json()
    assert body["code"] == "invalid_plan" and body["retryable"] is False
    assert "m_06" in body["message"]
    assert len(fake_model.calls) == 2


def test_schema_invalid_tool_input_is_repaired(client, fake_model, reels_request, reels_spec):
    bad = copy.deepcopy(reels_spec)
    bad["clips"][0]["transition_in"] = "wipe"
    fake_model.responses = [tool_response(bad), tool_response(reels_spec, "toolu_2")]
    assert client.post("/v1/plan", **multipart(reels_request)).status_code == 200


def test_no_tool_call_is_repaired(client, fake_model, reels_request, reels_spec):
    fake_model.responses = [text_response(), tool_response(reels_spec)]
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 200
    assert fake_model.calls[1]["messages"][-1]["content"][-1]["type"] == "text"


@pytest.mark.parametrize("header", [None, "Bearer wrong", f"Basic {TOKEN}"])
def test_auth_rejected(client, fake_model, reels_request, header):
    kwargs = multipart(reels_request)
    kwargs["headers"] = {"Authorization": header} if header else {}
    r = client.post("/v1/plan", **kwargs)
    assert r.status_code == 401
    assert r.json() == {"code": "unauthorized", "message": "missing or invalid bearer token", "retryable": False}
    assert fake_model.calls == []


def test_clip_cap(client, settings, fake_model, reels_request):
    settings.MAX_PLAN_CLIPS = 5
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 413
    assert r.json()["code"] == "too_many_clips"
    assert fake_model.calls == []


def test_missing_thumbnails(client, fake_model, reels_request):
    r = client.post("/v1/plan", **multipart(reels_request, thumbs=False))
    assert r.status_code == 400
    assert r.json()["code"] == "bad_request"


def test_bad_request_json(client, reels_request):
    bad = copy.deepcopy(reels_request)
    del bad["clips"]
    r = client.post("/v1/plan", **multipart(bad, thumbs=False))
    assert r.status_code == 400
    assert r.json()["code"] == "bad_request"


def test_plans_per_trip(client, settings, fake_model, reels_request, reels_spec):
    settings.PLANS_PER_TRIP = 2
    fake_model.responses = [tool_response(reels_spec) for _ in range(2)]
    for _ in range(2):
        assert client.post("/v1/plan", **multipart(reels_request)).status_code == 200
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 429
    assert r.json()["code"] == "rate_limited"


def test_upstream_timeout(client, fake_model, reels_request):
    fake_model.responses = [anthropic.APITimeoutError(request=httpx.Request("POST", "https://api.anthropic.com"))]
    r = client.post("/v1/plan", **multipart(reels_request))
    assert r.status_code == 504
    assert r.json()["code"] == "upstream_timeout" and r.json()["retryable"] is True
