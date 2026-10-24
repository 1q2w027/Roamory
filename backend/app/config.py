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
    # Moment evaluation (POST /v1/evaluate, TRD 8.2-8.3). Must fit the phone's 8 s timeout.
    STAGE2A_MODEL: str = "claude-haiku-5-5"
    STAGE2A_EFFORT: str = "low"
    STAGE2A_TIMEOUT_S: float = 3.0
    BUCKET_CAPACITY: int = 5
    BUCKET_REFILL_S: float = 30.0
    FAST_PER_HOUR: int = 100
    DESCRIBE_PER_HOUR: int = 60
    MAX_FRAME_BYTES: int = 400_000


@lru_cache
def get_settings() -> Settings:
    return Settings()
