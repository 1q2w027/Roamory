"""Pydantic mirrors of contracts/plan_request, edit_spec and style_presets. The schemas there are the source of truth."""
import json
from datetime import date
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Style = Literal["cinematic", "reels", "documentary", "vlog"]
Transition = Literal["cut", "fade", "dissolve"]


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


# --- Plan request -----------------------------------------------------------


class Destination(_Strict):
    country: str = Field(min_length=1)
    city: str | None = Field(min_length=1)


class PlanClip(_Strict):
    moment_id: str = Field(pattern=r"^[A-Za-z0-9_-]+$")
    t_from_ms: int = Field(ge=0)
    t_to_ms: int = Field(ge=0)
    duration_s: float = Field(gt=0)
    source: Literal["ai", "button", "local_fallback"]
    event_type: Literal["scenery", "landmark", "activity", "food", "social", "other"] | None
    description: str | None = Field(max_length=200)
    score: float | None = Field(ge=0, le=1)
    proposed_in_s: float = Field(ge=0)
    proposed_out_s: float = Field(gt=0)
    low_fps_lead_in_s: float = Field(ge=0)
    thumbnail_count: int = Field(ge=0, le=4)


class PlanRequest(_Strict):
    trip_id: str = Field(min_length=1)
    style: Style
    trip_type: str = Field(min_length=1)
    destination: Destination
    start_date: date
    target_s: float = Field(gt=0)
    effective_target_s: float = Field(gt=0)
    clips: list[PlanClip] = Field(min_length=1)


# --- Edit spec --------------------------------------------------------------


class Output(_Strict):
    width: int = Field(ge=1)
    height: int = Field(ge=1)
    fps: int = Field(ge=1)


class Title(_Strict):
    text: str = Field(min_length=1, max_length=40)
    subtitle: str | None = Field(max_length=60)
    duration_s: float = Field(gt=0)


class SpeedRamp(_Strict):
    from_: float = Field(alias="from", gt=0, le=8)
    to: float = Field(gt=0, le=8)
    over_s: float = Field(gt=0)


class EditClip(_Strict):
    moment_id: str = Field(min_length=1)
    in_s: float = Field(ge=0, description="Seconds from the start of the clip file.")
    out_s: float = Field(gt=0)
    transition_in: Transition = Field(description="On the first clip, fade/dissolve means from black.")
    transition_s: float = Field(ge=0, description="0 when transition_in is cut; otherwise the overlap.")
    speed_ramp: SpeedRamp | None
    caption: str | None = Field(max_length=200)


class Music(_Strict):
    track: str = Field(min_length=1)
    gain_db: float = Field(le=0)
    duck_original_audio: bool


class EndCard(_Strict):
    text: str = Field(min_length=1, max_length=40)
    duration_s: float = Field(gt=0)


class EditSpec(_Strict):
    trip_id: str = Field(min_length=1)
    style: Style
    output: Output
    title: Title
    clips: list[EditClip] = Field(min_length=1, description="In playback order.")
    music: Music
    end_card: EndCard


# --- Style presets ----------------------------------------------------------


class Range(_Strict):
    min: float = Field(ge=0)
    max: float = Field(ge=0)
    default: float = Field(ge=0)


class StylePreset(_Strict):
    target_s: Range
    clip_s: Range
    transition: Transition
    transition_s: Range
    aspect: Literal["16:9", "9:16"]
    output: Output
    title_s: float = Field(gt=0)
    end_card_s: float = Field(gt=0)
    music_track: str = Field(min_length=1)
    music_gain_db: float = Field(le=0)
    keep_original_audio: bool
    captions: bool
    allow_speed_ramp: bool


class StylePresets(_Strict):
    version: int = Field(ge=1)
    presets: dict[Style, StylePreset]


@lru_cache
def load_presets(path: Path) -> StylePresets:
    return StylePresets.model_validate(json.loads(Path(path).read_text()))
