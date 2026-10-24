import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { checkToolUse, type GuardRoots } from "../src/agent/guard";
import { checkResult, newSession, previewFrames, submit, type ToolContext } from "../src/agent/tools";
import type { AgentInput, AgentResult } from "../src/agent/types";
import { createWorkspace, removeWorkspace } from "../src/agent/workspace";
import { RENDER_ROOT } from "../src/server/config";
import { presets, validateAgentRequestParts } from "../src/server/validateAgent";
import { agentRequest, agentResult, STYLES } from "./helpers";

const parts = (style = STYLES[1]) => agentRequest(style).clips.map((c) => `${c.moment_id}.mp4`);

describe("agent request validation", () => {
  it.each(STYLES)("accepts the %s example with one part per clip", (style) => {
    const result = validateAgentRequestParts(JSON.stringify(agentRequest(style)), parts(style));
    expect(result).toEqual({ ok: true, request: agentRequest(style) });
  });

  it.each([
    ["no request", undefined, parts(), "missing request part"],
    ["not JSON", "{nope", parts(), "request is not JSON"],
    ["the schema broken", JSON.stringify({ ...agentRequest("reels"), style: "noir" }), parts(), "agent_request.schema.json"],
    ["a part missing", JSON.stringify(agentRequest("reels")), parts().slice(1), "do not match clips"],
    ["an extra part", JSON.stringify(agentRequest("reels")), [...parts(), "m_99.mp4"], "do not match clips"],
  ])("rejects %s", (_name, raw, names, message) => {
    const result = validateAgentRequestParts(raw, names);
    expect(result.ok).toBe(false);
    expect(!result.ok && result.message).toContain(message);
  });

  it("rejects a repeated moment_id", () => {
    const r = agentRequest("reels");
    r.clips[1].moment_id = r.clips[0].moment_id;
    const result = validateAgentRequestParts(JSON.stringify(r), r.clips.map((c) => `${c.moment_id}.mp4`));
    expect(result).toEqual({ ok: false, message: "a moment_id repeats" });
  });

  it("rejects a proposed window outside the uploaded clip", () => {
    for (const [inS, outS] of [[-1, 2], [5, 5], [10, 40]]) {
      const r = agentRequest("reels");
      Object.assign(r.clips[0], { proposed_in_s: inS, proposed_out_s: outS });
      expect(validateAgentRequestParts(JSON.stringify(r), parts()).ok).toBe(false);
    }
  });
});

describe("submit rules", () => {
  const request = agentRequest("reels");
  const rendered = { duration_s: 29.2 };
  const check = (edit: (r: AgentResult) => void, probe: { duration_s: number } | null = rendered) => {
    const r = agentResult();
    edit(r);
    return checkResult(r, request, probe);
  };

  it("accepts the example result against its request and render", () => {
    expect(checkResult(agentResult(), request, rendered)).toEqual([]);
  });

  it("rejects a result that breaks the schema", () => {
    expect(check((r) => (r.title.text = "x".repeat(41)))).toEqual([expect.stringContaining("agent_result.schema.json")]);
    expect(checkResult({ total_s: 30 }, request, rendered)).toEqual([expect.stringContaining("agent_result.schema.json")]);
  });

  it("needs every button clip", () => {
    expect(check((r) => (r.moments = r.moments.filter((m) => m.moment_id !== "m_03")))).toEqual([
      "m_03 is a button clip and must be in the video",
    ]);
  });

  it("rejects unknown and repeated moment_ids", () => {
    expect(check((r) => (r.moments[0].moment_id = "m_99"))).toEqual(["m_99 is not a moment_id in the request"]);
    expect(check((r) => (r.moments[1].moment_id = "m_01"))).toEqual(["m_01 appears more than once"]);
  });

  it("needs playback order and spans inside the video", () => {
    expect(check((r) => r.moments.reverse())).toContainEqual(expect.stringContaining("starts before"));
    expect(check((r) => (r.moments.at(-1)!.end_s = 31))).toEqual([expect.stringContaining("end_s <= total_s")]);
    expect(check((r) => (r.moments[0].start_s = r.moments[0].end_s))).toContainEqual(expect.stringContaining("start_s < end_s"));
  });

  it("needs total_s within ±10% of effective_target_s", () => {
    const errors = check((r) => (r.total_s = 26.9), { duration_s: 26.9 });
    expect(errors).toContainEqual(expect.stringContaining("outside ±10%"));
    expect(check((r) => (r.total_s = 27.1), { duration_s: 27.1 }).filter((e) => e.includes("±10%"))).toEqual([]);
  });

  it("needs a successful render whose duration matches total_s within 0.5 s", () => {
    expect(check(() => {}, null)).toEqual(["there is no successful render: call render_video first"]);
    expect(check(() => {}, { duration_s: 29.6 })).toEqual([expect.stringContaining("more than 0.5 s from the rendered duration")]);
  });

  it("completes the session only when accepted", () => {
    const ctx = { input: { request }, session: newSession() } as unknown as ToolContext;
    expect(submit(ctx, agentResult()).isError).toBe(true);
    expect(ctx.session.result).toBeNull();
    ctx.session.rendered = { ...rendered, width: 1080, height: 1920, fps: 30, size_bytes: 1 };
    expect(submit(ctx, agentResult()).isError).toBeUndefined();
    expect(ctx.session.result).toEqual(agentResult());
  });
});

describe("path guard", () => {
  const roots: GuardRoots = {
    workspace: "/work/a_1",
    writable: "/work/a_1/src",
    readable: [path.join(RENDER_ROOT, "src/remotion")],
  };
  const allowed = (tool: string, input: Record<string, unknown>) => checkToolUse(tool, input, roots) === null;

  it("allows reads in the workspace and the example sources", () => {
    expect(allowed("Read", { file_path: "manifest.json" })).toBe(true);
    expect(allowed("Read", { file_path: "/work/a_1/src/Video.tsx" })).toBe(true);
    expect(allowed("Read", { file_path: path.join(RENDER_ROOT, "src/remotion/styles/reels.tsx") })).toBe(true);
    expect(allowed("Glob", { pattern: "src/**/*.tsx" })).toBe(true);
    expect(allowed("Glob", { pattern: "*.tsx", path: path.join(RENDER_ROOT, "src/remotion/styles") })).toBe(true);
  });

  it("rejects reads outside them", () => {
    expect(allowed("Read", { file_path: "/etc/passwd" })).toBe(false);
    expect(allowed("Read", { file_path: "../a_2/manifest.json" })).toBe(false);
    expect(allowed("Read", { file_path: path.join(RENDER_ROOT, "../.env") })).toBe(false);
    expect(allowed("Read", { file_path: path.join(RENDER_ROOT, "src/server/config.ts") })).toBe(false);
    expect(allowed("Read", {})).toBe(false);
    expect(allowed("Glob", { pattern: "../**" })).toBe(false);
    expect(allowed("Glob", { pattern: "/etc/*" })).toBe(false);
    expect(allowed("Glob", { pattern: "*", path: "/" })).toBe(false);
  });

  it("allows writes only under the workspace's src/", () => {
    expect(allowed("Write", { file_path: "src/Video.tsx" })).toBe(true);
    expect(allowed("Edit", { file_path: "/work/a_1/src/parts/Title.tsx" })).toBe(true);
    expect(allowed("Write", { file_path: "Root.tsx" })).toBe(false);
    expect(allowed("Write", { file_path: "manifest.json" })).toBe(false);
    expect(allowed("Edit", { file_path: "src/../entry.ts" })).toBe(false);
    expect(allowed("Write", { file_path: path.join(RENDER_ROOT, "src/remotion/Highlight.tsx") })).toBe(false);
    expect(allowed("Write", { file_path: "/tmp/x.ts" })).toBe(false);
  });

  it("follows symlinks out of the workspace", () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "roamory-guard-"));
    const ws = path.join(dir, "ws");
    fs.mkdirSync(path.join(ws, "src"), { recursive: true });
    fs.mkdirSync(path.join(dir, "outside"));
    fs.symlinkSync(path.join(dir, "outside"), path.join(ws, "src", "link"));
    const r: GuardRoots = { workspace: ws, writable: path.join(ws, "src"), readable: [] };
    expect(checkToolUse("Write", { file_path: "src/link/x.ts" }, r)).not.toBeNull();
    expect(checkToolUse("Write", { file_path: "src/ok.ts" }, r)).toBeNull();
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("allows the agent's MCP tools and nothing else", () => {
    expect(allowed("mcp__roamory__render_video", {})).toBe(true);
    for (const tool of ["Bash", "WebFetch", "WebSearch", "Agent", "NotebookEdit", "mcp__other__x"]) expect(allowed(tool, {})).toBe(false);
  });
});

// Bundles the workspace and renders in headless Chrome, so it is slow (and needs `npx remotion browser ensure`).
describe("preview_frames", () => {
  let dir: string;
  let ctx: ToolContext;
  const write = (code: string) => fs.writeFileSync(path.join(ctx.ws.srcDir, "Video.tsx"), code);

  beforeAll(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "roamory-agent-"));
    const jobDir = path.join(dir, "job");
    fs.mkdirSync(path.join(jobDir, "clips"), { recursive: true });
    const input: AgentInput = { jobId: "a_test", request: agentRequest("reels"), preset: presets.reels };
    const ws = createWorkspace(path.join(dir, "work"), input, jobDir, path.join(dir, "no-music"));
    ctx = { input, ws, outputPath: path.join(jobDir, "out.mp4"), maxRenders: 1, onProgress: () => {}, signal: new AbortController().signal, session: newSession() };
  });

  afterAll(() => {
    removeWorkspace(ctx.ws);
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("returns a still of the starter composition at the preset's size", async () => {
    const result = await previewFrames(ctx, [0, 500]);
    expect(result.isError).toBeUndefined();
    expect(result.content[0]).toEqual({ type: "text", text: "1080x1920 at 30 fps, 90 frames" });
    expect(result.content.filter((c) => c.type === "image")).toHaveLength(2);
    // Clamped to the last frame.
    expect(result.content).toContainEqual({ type: "text", text: "frame 89" });
  }, 120_000);

  it("returns the bundle error as text for a Video.tsx that doesn't compile", async () => {
    write("export const durationInFrames = 30;\nexport const AgentVideo = () => <div>;\n");
    const result = await previewFrames(ctx, [0]);
    expect(result.isError).toBe(true);
    expect(result.content).toEqual([{ type: "text", text: expect.stringMatching(/^preview failed:\n/) }]);
  }, 120_000);

  it("returns the runtime error as text for a Video.tsx that throws", async () => {
    write('export const durationInFrames = 30;\nexport const AgentVideo = () => { throw new Error("broken on purpose"); };\n');
    const result = await previewFrames(ctx, [0]);
    expect(result.isError).toBe(true);
    expect(result.content[0]).toEqual({ type: "text", text: expect.stringContaining("broken on purpose") });
  }, 120_000);
});
