"""Bridge settings from studio/config.toml; tests pass their own values."""
import tomllib
from dataclasses import dataclass, fields
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACTS = ROOT / "contracts"


@dataclass
class Config:
    port: int = 8787
    claude: str = "claude"
    model: str = "claude-opus-5-5"
    max_turns: int = 80
    max_budget_usd: float = 5.0
    timeout_s: float = 900
    max_renders: int = 3
    max_clip_mb: int = 1000
    job_ttl_min: float = 60
    state_dir: str = "~/.roamory-studio"
    jobs_dir: str = "studio/.jobs"

    @property
    def state_path(self) -> Path:
        return Path(self.state_dir).expanduser()

    @property
    def jobs_path(self) -> Path:
        path = Path(self.jobs_dir).expanduser()
        return path if path.is_absolute() else ROOT / path


def load(path: Path = ROOT / "studio" / "config.toml") -> Config:
    values = tomllib.loads(path.read_text()) if path.exists() else {}
    known = {f.name for f in fields(Config)}
    return Config(**{k: v for k, v in values.items() if k in known})
