import { describe, expect, it } from "vitest";
import type { RenderRequest } from "../src/remotion/types";
import { validateRequest } from "../src/server/validate";
import { renderRequest, STYLES } from "./helpers";

const parts = (r: RenderRequest) => r.clips.map((c) => `${c.moment_id}.mp4`);
const check = (r: RenderRequest, names = parts(r)) => validateRequest(JSON.stringify(r), names);
const message = (r: ReturnType<typeof validateRequest>) => (r.ok ? "ok" : r.message);

describe("validateRequest", () => {
  it.each(STYLES)("accepts the %s example", (style) => {
    expect(check(renderRequest(style))).toMatchObject({ ok: true });
  });

  it("rejects a missing or non-JSON request part", () => {
    expect(message(validateRequest(undefined, []))).toMatch(/missing request/);
    expect(message(validateRequest("{nope", []))).toMatch(/not JSON/);
  });

  it("rejects a request that breaks the schema", () => {
    const r = renderRequest("cinematic") as unknown as Record<string, unknown>;
    delete r.context;
    expect(message(validateRequest(JSON.stringify(r), []))).toMatch(/render_request\.schema\.json/);
    const bad = renderRequest("cinematic");
    (bad.edit_spec.clips[0] as { transition_in: string }).transition_in = "slide";
    expect(message(check(bad))).toMatch(/render_request\.schema\.json/);
  });

  it("rejects file parts that don't match clips[]", () => {
    const r = renderRequest("reels");
    expect(message(check(r, parts(r).slice(1)))).toMatch(/file parts/);
    expect(message(check(r, [...parts(r), "m_99.mp4"]))).toMatch(/file parts/);
    expect(message(check(r, [...parts(r), parts(r)[0]]))).toMatch(/file parts/);
  });

  it("rejects clips[] that don't match the edit spec", () => {
    const r = renderRequest("reels");
    r.clips[0].moment_id = "m_99";
    expect(message(check(r))).toMatch(/does not match edit_spec/);
    const dup = renderRequest("reels");
    dup.clips[1].moment_id = dup.clips[0].moment_id;
    expect(message(check(dup))).toMatch(/repeats/);
  });

  it("rejects a trim outside the uploaded file", () => {
    const r = renderRequest("vlog");
    r.edit_spec.clips[2].out_s = r.clips[2].duration_s + 0.5;
    expect(message(check(r))).toMatch(/outside the uploaded/);
  });

  it("checks transition_s against cut, and the ramp length", () => {
    const cut = renderRequest("vlog");
    cut.edit_spec.clips[1].transition_s = 0.5;
    expect(message(check(cut))).toMatch(/transition_s/);
    const ramp = renderRequest("cinematic");
    ramp.edit_spec.clips[2].speed_ramp = { from: 4, to: 1, over_s: 9 };
    expect(message(check(ramp))).toMatch(/over_s/);
  });
});
