// Mirrors contracts/edit_spec.schema.json and render_request.schema.json (snake_case, as on the wire).

export type Style = "cinematic" | "reels" | "documentary" | "vlog";
export type Transition = "cut" | "fade" | "dissolve";

export type SpeedRamp = { from: number; to: number; over_s: number };

export type Clip = {
  moment_id: string;
  in_s: number;
  out_s: number;
  transition_in: Transition;
  transition_s: number;
  speed_ramp: SpeedRamp | null;
  caption: string | null;
};

export type EditSpec = {
  trip_id: string;
  style: Style;
  output: { width: number; height: number; fps: number };
  title: { text: string; subtitle: string | null; duration_s: number };
  clips: Clip[];
  music: { track: string; gain_db: number; duck_original_audio: boolean };
  end_card: { text: string; duration_s: number };
};

export type TripContext = {
  destination: { country: string; city: string | null };
  trip_type: string;
  start_date: string;
};

export type RenderRequest = {
  edit_spec: EditSpec;
  context: TripContext;
  clips: { moment_id: string; duration_s: number; has_audio: boolean }[];
};

/** Input props of the Highlight composition. */
export type HighlightProps = {
  spec: EditSpec;
  context: TripContext;
  /** Per moment_id: an http(s) URL, or a path under public/ (Studio and the smoke script). */
  clips: Record<string, { src: string; has_audio: boolean }>;
  /** Path under public/, or null to render without music (like the iOS renderer when a track is missing). */
  music_src: string | null;
};
