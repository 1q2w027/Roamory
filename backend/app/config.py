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

    # Moment evaluation (POST /v1/evaluate, TRD 8.2-8.3). 2a + 2b must fit the phone's 8 s timeout.
    STAGE2A_MODEL: str = "claude-haiku-5-5"
    STAGE2A_EFFORT: str = "low"
    STAGE2A_TIMEOUT_S: float = 3.0
    STAGE2A_FALLBACKS: bool = False  # Haiku has no server-side refusal fallback
    STAGE2B_MODEL: str = "claude-sonnet-5-5"
    STAGE2B_EFFORT: str = "low"
    STAGE2B_TIMEOUT_S: float = 4.0
    STAGE2B_FALLBACKS: bool = True
    S2_WEIGHTS: dict[str, float] = {
        "pref": 0.35,
        "interest": 0.25,
        "significance": 0.20,
        "quality": 0.10,
        "novelty": 0.10,
    }
    SAVE_THRESHOLD: float = 0.60
    SAVE_ANYWAY_THRESHOLD: float = 0.75
    # A 2a score this close to SAVE_THRESHOLD goes to 2b.
    UNCERTAIN_BAND: float = 0.08
    BUCKET_CAPACITY: int = 5
    BUCKET_REFILL_S: float = 30.0
    FAST_PER_HOUR: int = 100
    STRONG_PER_HOUR: int = 15
    DESCRIBE_PER_HOUR: int = 60
    MAX_FRAME_BYTES: int = 400_000


@lru_cache
def get_settings() -> Settings:
    return Settings()
