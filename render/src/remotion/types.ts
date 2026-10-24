// Shared by the agent's working examples (styles/, speedRamp.ts) and the server (snake_case, as on the wire).

export type Style = "cinematic" | "reels" | "documentary" | "vlog";

export type SpeedRamp = { from: number; to: number; over_s: number };

export type TripContext = {
  destination: { country: string; city: string | null };
  trip_type: string;
  start_date: string;
};

export type Title = { text: string; subtitle: string | null; duration_s: number };
