// Mirrors contracts/agent_request.schema.json, agent_result.schema.json and style_presets.json (snake_case, as on the wire).
import type { Style, TripContext } from "../remotion/types";

export type AgentClip = {
  moment_id: string;
  source: "ai" | "button" | "local_fallback";
  event_type: string | null;
  description: string | null;
  score: number | null;
  t_from_ms: number;
  duration_s: number;
  has_audio: boolean;
  proposed_in_s: number;
  proposed_out_s: number;
  low_fps_lead_in_s: number;
};

export type AgentRequest = {
  trip_id: string;
  style: Style;
  target_s: number;
  effective_target_s: number;
  context: TripContext;
  clips: AgentClip[];
};

export type AgentResult = {
  total_s: number;
  title: { text: string; subtitle: string | null };
  moments: { moment_id: string; start_s: number; end_s: number }[];
};

type Range = { min: number; max: number; default: number };

export type StylePreset = {
  target_s: Range;
  clip_s: Range;
  transition: "cut" | "fade" | "dissolve";
  transition_s: Range;
  aspect: string;
  output: { width: number; height: number; fps: number };
  title_s: number;
  end_card_s: number;
  music_track: string;
  music_gain_db: number;
  keep_original_audio: boolean;
  captions: boolean;
  allow_speed_ramp: boolean;
};

/** What an agent job runs on. The uploaded clips are in `{workDir}/clips/{moment_id}.mp4`. */
export type AgentInput = { jobId: string; request: AgentRequest; preset: StylePreset };
