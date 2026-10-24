import { describe, expect, it } from "vitest";
import { segments, stepRates, type RampedClip } from "../src/remotion/speedRamp";

// speedRamp.ts is one of the agent's working examples.
describe("speed ramp", () => {
  const clip = (ramp: RampedClip["speed_ramp"], out_s = 7): RampedClip => ({ in_s: 0, out_s, speed_ramp: ramp });

  it("uses the README step rates", () => {
    expect(stepRates({ from: 4, to: 1, over_s: 2 })).toEqual([4, 3, 2, 1]);
  });

  it("splits a ramp into 4 constant-rate steps and the rest at 1x", () => {
    const segs = segments(clip({ from: 4, to: 1, over_s: 2 }));
    expect(segs.map((s) => s.rate)).toEqual([4, 3, 2, 1, 1]);
    expect(segs.map((s) => s.source_start_s)).toEqual([0, 0.5, 1, 1.5, 2]);
    // 5 s + 0.5 (1/4 + 1/3 + 1/2 + 1) = 6.042 s.
    expect(segs.reduce((sum, s) => sum + s.output_s, 0)).toBeCloseTo(6.0417, 3);
  });

  it("has no 1x tail when the ramp covers the whole trim", () => {
    expect(segments(clip({ from: 2, to: 1, over_s: 3 }, 3))).toHaveLength(4);
  });

  it("is one segment without a ramp", () => {
    expect(segments(clip(null))).toEqual([{ source_start_s: 0, output_start_s: 0, output_s: 7, rate: 1 }]);
  });
});
