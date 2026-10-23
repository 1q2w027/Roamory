from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Read from the repo-root .env (see .env.example), then backend/.env, then the environment."""

    model_config = SettingsConfigDict(
        env_file=(REPO_ROOT / ".env", Path(__file__).resolve().parents[1] / ".env"),
        extra="ignore",
    )

    APP_TOKEN: str = ""
    ANTHROPIC_API_KEY: str = ""
    PLANNER_MODEL: str = "claude-opus-5-5"
    PLANNER_EFFORT: str = "medium"
    PLAN_TIMEOUT_S: float = 25.0
    # 4 thumbnails per clip; keep clips x 4 under the API's per-request image limit.
    MAX_PLAN_CLIPS: int = 24
    PLANS_PER_TRIP: int = 5
    STYLE_PRESETS_PATH: Path = REPO_ROOT / "contracts" / "style_presets.json"


@lru_cache
def get_settings() -> Settings:
    return Settings()
