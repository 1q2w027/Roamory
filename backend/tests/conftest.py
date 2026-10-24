import json
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.config import REPO_ROOT, Settings, get_settings
from app.main import app
from app.evaluate.budget import BudgetBook
from app.evaluate.service import Evaluator

EXAMPLES = REPO_ROOT / "contracts" / "examples"
TOKEN = "test-token"


def load_example(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text())


def text_response(text: str = "Here is my answer.") -> SimpleNamespace:
    return SimpleNamespace(content=[SimpleNamespace(type="text", text=text)], stop_reason="end_turn")


class FakeModelClient:
    """Stands in for AsyncAnthropic: returns queued responses (or raises queued exceptions) in order."""

    def __init__(self):
        self.responses: list = []
        self.calls: list[dict] = []
        self.beta = SimpleNamespace(messages=SimpleNamespace(create=self._create))

    async def _create(self, **kwargs):
        # Copy messages, in case the caller appends to the same list after the call.
        self.calls.append({**kwargs, "messages": list(kwargs["messages"])})
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


@pytest.fixture
def settings() -> Settings:
    return Settings(_env_file=None, APP_TOKEN=TOKEN)


@pytest.fixture
def fake_model() -> FakeModelClient:
    return FakeModelClient()


@pytest.fixture
def client(settings, fake_model):
    app.dependency_overrides[get_settings] = lambda: settings
    app.state.evaluator = Evaluator(fake_model, settings, BudgetBook(settings))
    yield TestClient(app)  # not entered as a context manager, so lifespan (real client) doesn't run
    app.dependency_overrides.clear()


def verdict(**kw):
    """A valid Stage 2 verdict (contracts/evaluation verdict) with overrides."""
    from app.evaluate.models import ModelVerdict

    base = dict(
        event_type="scenery", matched_preferences=["scenery"], save_decision="save",
        best_frame_index=2, window_hint_s={"pre": 15, "post": 15},
        description="A temple gate at dusk", reason="Scenic landmark",
    )
    return ModelVerdict.model_validate(base | kw)


JPEG = b"\xff\xd8\xff\xe0fake-jpeg"


def ok(**kw) -> SimpleNamespace:
    """A model response whose structured output is verdict(**kw)."""
    return text_response(json.dumps(verdict(**kw).model_dump()))


def evaluate_multipart(ctx: dict, n_frames: int = 3, frame: bytes = JPEG, names: list[str] | None = None) -> dict:
    """POST /v1/evaluate kwargs: the context part plus frame parts (frame_0.jpg ... by default)."""
    files = [("context", ("context.json", json.dumps(ctx).encode(), "application/json"))]
    for name in names or [f"frame_{k}.jpg" for k in range(n_frames)]:
        files.append((name, (name, frame, "image/jpeg")))
    return {"files": files, "headers": {"Authorization": f"Bearer {TOKEN}"}}
