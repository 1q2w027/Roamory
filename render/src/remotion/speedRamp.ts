import type { SpeedRamp } from "./types";

/** A run of one clip played at a constant rate. Seconds; output times are from the clip's start. */
export type Segment = { source_start_s: number; output_start_s: number; output_s: number; rate: number };

/** A clip's source range in seconds, and its ramp if any. */
export type RampedClip = { in_s: number; out_s: number; speed_ramp: SpeedRamp | null };

/** Rates of the 4 equal source steps: r_k = from + (to - from)·k/3. */
export function stepRates(ramp: SpeedRamp): number[] {
  return [0, 1, 2, 3].map((k) => ramp.from + ((ramp.to - ramp.from) * k) / 3);
}

/**
 * The first over_s source seconds in 4 equal steps at constant rates, then the rest at 1x.
 * Without a ramp, one segment at 1x.
 */
export function segments(clip: RampedClip): Segment[] {
  const ramp = clip.speed_ramp;
  if (!ramp) {
    return [{ source_start_s: clip.in_s, output_start_s: 0, output_s: clip.out_s - clip.in_s, rate: 1 }];
  }
  const step = ramp.over_s / 4;
  const result: Segment[] = [];
  let output = 0;
  stepRates(ramp).forEach((rate, k) => {
    result.push({ source_start_s: clip.in_s + k * step, output_start_s: output, output_s: step / rate, rate });
    output += step / rate;
  });
  const rest = clip.out_s - clip.in_s - ramp.over_s;
  if (rest > 0) {
    result.push({ source_start_s: clip.in_s + ramp.over_s, output_start_s: output, output_s: rest, rate: 1 });
  }
  return result;
}
