import type { Clip, EditSpec, SpeedRamp } from "./types";

// Port of ios/RoamoryKit/Sources/RoamoryKit/Edit/EditTimeline.swift (contracts README, "Duration").
// Keep in step with it and with backend/app/plan/validate.py.

export type Slot = { moment_id: string; start_s: number; end_s: number };

/** Rates of the 4 equal source steps: r_k = from + (to - from)·k/3. */
export function stepRates(ramp: SpeedRamp): number[] {
  return [0, 1, 2, 3].map((k) => ramp.from + ((ramp.to - ramp.from) * k) / 3);
}

/** Output seconds for one clip. A ramp plays its first over_s source seconds in 4 equal steps. */
export function outputLengthS(clip: Clip): number {
  const length = clip.out_s - clip.in_s;
  const ramp = clip.speed_ramp;
  if (!ramp) return length;
  return length - ramp.over_s + stepRates(ramp).reduce((sum, r) => sum + ramp.over_s / 4 / r, 0);
}

/** Overlap with the previous clip. The first clip's fade starts from black and overlaps nothing. */
export function overlapS(clips: Clip[], index: number): number {
  if (index === 0 || clips[index].transition_in === "cut") return 0;
  return clips[index].transition_s;
}

export function slots(spec: EditSpec): Slot[] {
  const result: Slot[] = [];
  let end = 0;
  spec.clips.forEach((clip, i) => {
    const start = end - overlapS(spec.clips, i);
    end = start + outputLengthS(clip);
    result.push({ moment_id: clip.moment_id, start_s: start, end_s: end });
  });
  return result;
}

/** Clip output lengths, minus transition overlaps, plus the end card. The title adds nothing. */
export function totalDurationS(spec: EditSpec): number {
  return (slots(spec).at(-1)?.end_s ?? 0) + spec.end_card.duration_s;
}
