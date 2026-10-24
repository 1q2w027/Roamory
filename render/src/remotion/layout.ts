import { overlapS, slots, totalDurationS } from "./timeline";
import type { Clip, EditSpec } from "./types";

/** One clip placed on the composition, in frames. */
export type PlacedClip = {
  clip: Clip;
  index: number;
  from: number;
  durationInFrames: number;
  /** Frames shared with the previous clip (0 for the first clip and cuts). */
  overlapIn: number;
  /** Frames shared with the next clip. */
  overlapOut: number;
};

export type Layout = {
  fps: number;
  clips: PlacedClip[];
  endCard: { from: number; durationInFrames: number };
  titleFrames: number;
  durationInFrames: number;
};

/**
 * Every boundary is the golden timeline's time rounded to a frame, never a sum of rounded lengths,
 * so the video's cut points stay within half a frame of `slots()` however many clips there are.
 */
export function layout(spec: EditSpec): Layout {
  const fps = spec.output.fps;
  const f = (s: number) => Math.round(s * fps);
  const timeline = slots(spec);
  const clips = spec.clips.map((clip, i): PlacedClip => {
    const from = f(timeline[i].start_s);
    return {
      clip,
      index: i,
      from,
      durationInFrames: f(timeline[i].end_s) - from,
      overlapIn: overlapS(spec.clips, i) > 0 ? f(timeline[i - 1].end_s) - from : 0,
      overlapOut: 0,
    };
  });
  clips.forEach((c, i) => {
    if (i + 1 < clips.length) c.overlapOut = clips[i + 1].overlapIn;
  });
  const endFrom = f(timeline.at(-1)!.end_s);
  const durationInFrames = f(totalDurationS(spec));
  return {
    fps,
    clips,
    endCard: { from: endFrom, durationInFrames: durationInFrames - endFrom },
    titleFrames: Math.min(f(spec.title.duration_s), endFrom),
    durationInFrames,
  };
}
