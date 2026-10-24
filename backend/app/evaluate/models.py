"""Pydantic mirrors of contracts/evaluate_context and contracts/evaluation. The schemas there are the source of truth."""
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.plan.models import Style

Purpose = Literal["select", "describe"]
Tier = Literal["2a", "2b"]
EventType = Literal["scenery", "landmark", "activity", "food", "social", "other"]
SaveDecision = Literal["save", "skip", "uncertain"]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --- Request context --------------------------------------------------------


class Destination(_Strict):
    continent: str | None = Field(min_length=1)
    country: str = Field(min_length=1)
    city: str | None = Field(min_length=1)


class LocalSignals(_Strict):
    score: float = Field(ge=0, le=1)
    novelty: float = Field(ge=0, le=1)
    sharpness: float = Field(ge=0)
    change: float = Field(ge=0)
    motion: float = Field(ge=0)
    forced: bool


class EvaluateContext(_Strict):
    version: Literal[1]
    trip_id: str = Field(min_length=1)
    install_id: str = Field(min_length=1)
    purpose: Purpose
    sample_t_ms: int = Field(ge=0)
    style: Style
    trip_type: str = Field(min_length=1)
    destination: Destination
    length_days: int = Field(ge=1)
    local: LocalSignals
    recent_descriptions: list[str] = Field(max_length=5)


# --- Response -----------------------------------------------------------------


class WindowHint(_Strict):
    pre: int = Field(ge=0, le=30)
    post: int = Field(ge=0, le=30)


class ModelVerdict(_Strict):
    """What the model returns (TRD 8.2). Also its structured-output schema."""

    event_type: EventType
    matched_preferences: list[str]
    preference_alignment: float = Field(ge=0, le=1)
    visual_interest: float = Field(ge=0, le=1)
    significance: float = Field(ge=0, le=1)
    visual_quality: float = Field(ge=0, le=1)
    save_decision: SaveDecision
    best_frame_index: int = Field(ge=0, le=2)
    window_hint_s: WindowHint
    description: str = Field(max_length=200)
    reason: str = Field(max_length=200)


class Evaluation(_Strict):
    version: Literal[1] = 1
    keep: bool
    s2: float = Field(ge=0, le=1)
    tier: Tier
    latency_ms: int = Field(ge=0)
    verdict: ModelVerdict
