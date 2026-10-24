import { describe, expect, it } from "vitest";
import { layout } from "../src/remotion/layout";
import { segments } from "../src/remotion/speedRamp";
import { outputLengthS, slots, stepRates, totalDurationS } from "../src/remotion/timeline";
import type { Clip } from "../src/remotion/types";
import { editSpec, golden, renderRequest, STYLES } from "./helpers";

// Golden timelines are rounded to 1 ms (contracts README, "Golden timelines").
const MS = 1e-3 + 1e-9;

describe.each(STYLES)("timeline: %s", (style) => {
  const want = golden(style);

  it("matches the golden timeline", () => {
    const got = slots(editSpec(style));
    expect(got.map((s) => s.moment_id)).toEqual(want.slots.map((s) => s.moment_id));
    got.forEach((s, i) => {
      expect(Math.abs(s.start_s - want.slots[i].start_s)).toBeLessThanOrEqual(MS);
      expect(Math.abs(s.end_s - want.slots[i].end_s)).toBeLessThanOrEqual(MS);
    });
    expect(Math.abs(got.at(-1)!.end_s - want.end_card_start_s)).toBeLessThanOrEqual(MS);
    expect(Math.abs(totalDurationS(editSpec(style)) - want.total_s)).toBeLessThanOrEqual(MS);
  });

  it("is the same for the rebased spec in the render request", () => {
    expect(slots(renderRequest(style).edit_spec)).toEqual(slots(editSpec(style)));
  });

  it("lays out frames at the golden times", () => {
    const spec = renderRequest(style).edit_spec;
    const plan = layout(spec);
    const fps = spec.output.fps;
    expect(plan.durationInFrames).toBe(Math.round(want.total_s * fps));
    plan.clips.forEach((c, i) => {
      expect(c.from).toBe(Math.round(want.slots[i].start_s * fps));
      expect(c.from + c.durationInFrames).toBe(Math.round(want.slots[i].end_s * fps));
    });
    expect(plan.endCard.from).toBe(Math.round(want.end_card_start_s * fps));
    // TransitionSeries places each sequence after the last minus the transition: it must land on `from`.
    let cursor = 0;
    for (const c of plan.clips) {
      expect(cursor - c.overlapIn).toBe(c.from);
      cursor = c.from + c.durationInFrames;
    }
    expect(cursor + plan.endCard.durationInFrames).toBe(plan.durationInFrames);
  });
});

describe("speed ramp", () => {
  const clip = (ramp: Clip["speed_ramp"], out_s = 7): Clip => ({
    moment_id: "m",
    in_s: 0,
    out_s,
    transition_in: "cut",
    transition_s: 0,
    speed_ramp: ramp,
    caption: null,
  });

  it("uses the README step rates", () => {
    expect(stepRates({ from: 4, to: 1, over_s: 2 })).toEqual([4, 3, 2, 1]);
  });

  it("splits a ramp into 4 constant-rate steps and the rest at 1x", () => {
    const c = clip({ from: 4, to: 1, over_s: 2 });
    const segs = segments(c);
    expect(segs.map((s) => s.rate)).toEqual([4, 3, 2, 1, 1]);
    expect(segs.map((s) => s.source_start_s)).toEqual([0, 0.5, 1, 1.5, 2]);
    const total = segs.reduce((sum, s) => sum + s.output_s, 0);
    expect(total).toBeCloseTo(outputLengthS(c), 9);
    // The cinematic m_03 slot: 5 s + 0.5 (1/4 + 1/3 + 1/2 + 1) = 6.042 s.
    expect(total).toBeCloseTo(6.0417, 3);
  });

  it("has no 1x tail when the ramp covers the whole trim", () => {
    expect(segments(clip({ from: 2, to: 1, over_s: 3 }, 3))).toHaveLength(4);
  });

  it("is one segment without a ramp", () => {
    expect(segments(clip(null))).toEqual([{ source_start_s: 0, output_start_s: 0, output_s: 7, rate: 1 }]);
  });
});
