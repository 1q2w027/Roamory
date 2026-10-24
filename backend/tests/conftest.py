import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.config import REPO_ROOT, Settings, get_settings
from app.main import app
from app.plan import router as plan_router
from app.plan.prompt import TOOL_NAME
from app.plan.service import Planner

EXAMPLES = REPO_ROOT / "contracts" / "examples"
STYLES = ["cinematic", "reels", "documentary", "vlog"]
TOKEN = "test-token"


def load_example(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text())


def tool_response(spec: dict, block_id: str = "toolu_1") -> SimpleNamespace:
    block = SimpleNamespace(type="tool_use", id=block_id, name=TOOL_NAME, input=spec)
    return SimpleNamespace(content=[block], stop_reason="tool_use")


def text_response(text: str = "Here is my plan.") -> SimpleNamespace:
    return SimpleNamespace(content=[SimpleNamespace(type="text", text=text)], stop_reason="end_turn")


class FakeModelClient:
    """Stands in for AsyncAnthropic: returns queued responses (or raises queued exceptions) in order."""

    def __init__(self):
        self.responses: list = []
        self.calls: list[dict] = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create))

    async def _create(self, **kwargs):
        # Copy messages: the planner appends to the same list after the call.
        self.calls.append({**kwargs, "messages": list(kwargs["messages"])})
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, APP_TOKEN=TOKEN, MAX_PLAN_CLIPS=24, PLANS_PER_TRIP=5)


@pytest.fixture
def fake_model() -> FakeModelClient:
    return FakeModelClient()


@pytest.fixture
def client(settings, fake_model):
    plan_router._plan_counts.clear()
    app.dependency_overrides[get_settings] = lambda: settings
    app.state.planner = Planner(fake_model, settings)
    yield TestClient(app)  # not entered as a context manager, so lifespan (real client) doesn't run
    app.dependency_overrides.clear()


def multipart(plan_request: dict, thumbs: bool = True) -> dict:
    files = [("request", ("request.json", json.dumps(plan_request).encode(), "application/json"))]
    if thumbs:
        for c in plan_request["clips"]:
            for k in range(c["thumbnail_count"]):
                name = f"{c['moment_id']}_{k}.jpg"
                files.append((name, (name, b"\xff\xd8\xff\xe0fake-jpeg", "image/jpeg")))
    return {"files": files, "headers": {"Authorization": f"Bearer {TOKEN}"}}


def verdict(**kw):
    """A valid Stage 2 verdict (contracts/evaluation verdict) with overrides."""
    from app.evaluate.models import ModelVerdict

    base = dict(
        event_type="scenery", matched_preferences=["scenery"], preference_alignment=0.8,
        visual_interest=0.6, significance=0.5, visual_quality=0.9, save_decision="save",
        best_frame_index=2, window_hint_s={"pre": 15, "post": 15},
        description="A temple gate at dusk", reason="Scenic landmark",
    )
    return ModelVerdict.model_validate(base | kw)
