import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { createSdkMcpServer, tool } from "@anthropic-ai/claude-agent-sdk";
import { bundle } from "@remotion/bundler";
import { makeCancelSignal, renderMedia, renderStill, selectComposition } from "@remotion/renderer";
import type { ValidateFunction } from "ajv/dist/2020.js";
import { z } from "zod";
import { RENDER_ROOT } from "../server/config";
import { freePort } from "../server/renderer";
import { ajv, schemaErrors, schemaId } from "../server/validate";
import { MCP_SERVER } from "./guard";
import { extractFrame, probe, type Probe } from "./media";
import type { AgentInput, AgentRequest, AgentResult } from "./types";
import type { Workspace } from "./workspace";

type ToolResult = { content: ({ type: "text"; text: string } | { type: "image"; data: string; mimeType: string })[]; isError?: boolean };

/** What one agent job has done so far. run.ts logs the counts. */
export type Session = {
  looks: number;
  previews: number;
  renders: number;
  /** ffprobe of the latest render, or null if there is none or it failed. */
  rendered: Probe | null;
  /** Set once submit passes; the job completes with it. */
  result: AgentResult | null;
  bundle: { key: string; serveUrl: string } | null;
};

export type ToolContext = {
  input: AgentInput;
  ws: Workspace;
  /** Where render_video writes the video (the job's out.mp4). */
  outputPath: string;
  maxRenders: number;
  onProgress: (progress: number) => void;
  signal: AbortSignal;
  session: Session;
};

export const newSession = (): Session => ({ looks: 0, previews: 0, renders: 0, rendered: null, result: null, bundle: null });

/** The composition Root.tsx registers. */
const COMPOSITION = "AgentVideo";
/** Long side of preview_frames' stills. */
const PREVIEW_PX = 768;
/** Error text handed back to the agent is cut to this. */
const MAX_ERROR_CHARS = 4000;
/** Progress before the first render; render_video's own progress fills the rest. */
const PRE_RENDER_PROGRESS = 0.2;

const text = (t: string, isError = false): ToolResult => ({ content: [{ type: "text", text: t }], ...(isError ? { isError } : {}) });
/** The error and its stack, without frames from node_modules or Node itself. */
const errorText = (e: unknown) => {
  const lines = (e instanceof Error ? (e.stack ?? e.message) : String(e)).split("\n");
  const s = lines.filter((l) => !/^\s+at .*(node_modules|node:)/.test(l) && l !== "undefined").join("\n");
  return s.length > MAX_ERROR_CHARS ? `${s.slice(0, MAX_ERROR_CHARS)}…` : s;
};
const nudge = (ctx: ToolContext) => {
  const calls = ctx.session.looks + ctx.session.previews;
  ctx.onProgress(Math.min(PRE_RENDER_PROGRESS, 0.02 + 0.01 * calls));
};

/** look_at_clip: frames of one uploaded clip at the given source seconds. */
export async function lookAtClip(ctx: ToolContext, momentId: string, times: number[]): Promise<ToolResult> {
  const clip = ctx.input.request.clips.find((c) => c.moment_id === momentId);
  if (!clip) return text(`unknown moment_id ${momentId}`, true);
  ctx.session.looks++;
  nudge(ctx);
  const file = path.join(ctx.ws.publicDir, "clips", `${momentId}.mp4`);
  const content: ToolResult["content"] = [];
  for (const t of times) {
    const at = Math.min(Math.max(0, t), Math.max(0, clip.duration_s - 0.05));
    try {
      const jpeg = await extractFrame(file, at, ctx.signal);
      content.push({ type: "text", text: `${momentId} at ${at.toFixed(2)} s` }, { type: "image", data: jpeg.toString("base64"), mimeType: "image/jpeg" });
    } catch (e) {
      content.push({ type: "text", text: `${momentId} at ${at.toFixed(2)} s: no frame (${e instanceof Error ? e.message : e})` });
    }
  }
  return { content };
}

/** preview_frames: stills of the agent's composition, or the bundle or runtime error as text. */
export async function previewFrames(ctx: ToolContext, frames: number[]): Promise<ToolResult> {
  ctx.session.previews++;
  nudge(ctx);
  const cancel = cancelOn(ctx.signal);
  try {
    const { serveUrl, composition, inputProps } = await prepare(ctx);
    const { width, height, durationInFrames } = composition;
    const scale = Math.min(1, PREVIEW_PX / Math.max(width, height));
    const content: ToolResult["content"] = [{ type: "text", text: `${width}x${height} at ${composition.fps} fps, ${durationInFrames} frames` }];
    for (const requested of frames) {
      const frame = Math.min(Math.max(0, Math.round(requested)), durationInFrames - 1);
      const { buffer } = await renderStill({
        composition,
        serveUrl,
        frame,
        inputProps,
        port: await freePort(),
        imageFormat: "jpeg",
        jpegQuality: 80,
        scale,
        output: null,
        cancelSignal: cancel.cancelSignal,
        logLevel: "error",
      });
      content.push({ type: "text", text: `frame ${frame}` }, { type: "image", data: buffer!.toString("base64"), mimeType: "image/jpeg" });
    }
    return { content };
  } catch (e) {
    return text(`preview failed:\n${errorText(e)}`, true);
  } finally {
    cancel.dispose();
  }
}

/** render_video: the whole composition to out.mp4, then ffprobe. At most maxRenders per job. */
export async function renderVideo(ctx: ToolContext): Promise<ToolResult> {
  const { session } = ctx;
  if (session.renders >= ctx.maxRenders) {
    return text(`render limit reached (${ctx.maxRenders}). ${session.rendered ? "Submit the last render." : "No render succeeded."}`, true);
  }
  session.renders++;
  session.rendered = null;
  fs.rmSync(ctx.outputPath, { force: true });
  const cancel = cancelOn(ctx.signal);
  try {
    const { serveUrl, composition, inputProps } = await prepare(ctx);
    await renderMedia({
      composition,
      serveUrl,
      inputProps,
      port: await freePort(),
      codec: "h264",
      audioCodec: "aac",
      outputLocation: ctx.outputPath,
      cancelSignal: cancel.cancelSignal,
      logLevel: "error",
      onProgress: ({ progress }) => ctx.onProgress(PRE_RENDER_PROGRESS + (1 - PRE_RENDER_PROGRESS) * 0.95 * progress),
    });
    session.rendered = await probe(ctx.outputPath);
    const left = ctx.maxRenders - session.renders;
    return text(`rendered: ${JSON.stringify(session.rendered)}. ${left} render(s) left.`);
  } catch (e) {
    fs.rmSync(ctx.outputPath, { force: true });
    return text(`render failed:\n${errorText(e)}`, true);
  } finally {
    cancel.dispose();
  }
}

/** submit: checks the result against agent_result.schema.json and the result rules; on success the job completes. */
export function submit(ctx: ToolContext, result: AgentResult): ToolResult {
  const errors = checkResult(result, ctx.input.request, ctx.session.rendered);
  if (errors.length) return text(`not accepted:\n- ${errors.join("\n- ")}`, true);
  ctx.session.result = result;
  return text("Accepted. The video is done; stop now.");
}

const validateResult = ajv.getSchema(schemaId("agent_result")) as ValidateFunction<AgentResult>;

/**
 * contracts/README.md, "Agent result rules". `rendered` is ffprobe of the latest render (null if none succeeded).
 * Returns the broken rules, empty when the result is accepted.
 */
export function checkResult(result: unknown, request: AgentRequest, rendered: Pick<Probe, "duration_s"> | null): string[] {
  if (!validateResult(result)) return [`does not match agent_result.schema.json: ${schemaErrors(validateResult)}`];
  const errors: string[] = [];
  const known = new Set(request.clips.map((c) => c.moment_id));
  const used = result.moments.map((m) => m.moment_id);
  for (const id of used.filter((id) => !known.has(id))) errors.push(`${id} is not a moment_id in the request`);
  for (const id of new Set(used.filter((id, i) => used.indexOf(id) !== i))) errors.push(`${id} appears more than once`);
  for (const c of request.clips.filter((c) => c.source === "button" && !used.includes(c.moment_id))) {
    errors.push(`${c.moment_id} is a button clip and must be in the video`);
  }
  result.moments.forEach((m, i) => {
    if (!(m.start_s >= 0 && m.start_s < m.end_s && m.end_s <= result.total_s + 1e-6)) {
      errors.push(`${m.moment_id}: need 0 <= start_s < end_s <= total_s, got [${m.start_s}, ${m.end_s}]`);
    }
    if (i > 0 && m.start_s < result.moments[i - 1].start_s) errors.push(`${m.moment_id} starts before the moment listed before it`);
  });
  const target = request.effective_target_s;
  if (Math.abs(result.total_s - target) > 0.1 * target + 1e-6) {
    errors.push(`total_s ${result.total_s} is outside ±10% of effective_target_s ${target} (${(0.9 * target).toFixed(2)} to ${(1.1 * target).toFixed(2)})`);
  }
  if (!rendered) errors.push("there is no successful render: call render_video first");
  else if (Math.abs(result.total_s - rendered.duration_s) > 0.5) {
    errors.push(`total_s ${result.total_s} is more than 0.5 s from the rendered duration ${rendered.duration_s}`);
  }
  return errors;
}

/** The in-process MCP server with the four agent tools. */
export function createToolServer(ctx: ToolContext) {
  return createSdkMcpServer({
    name: MCP_SERVER,
    version: "1.0.0",
    alwaysLoad: true,
    tools: [
      tool(
        "look_at_clip",
        "Frames of one uploaded clip as images, at the given seconds from the start of the clip's file (up to 6 per call). This is how you watch the clips.",
        { moment_id: z.string(), times_s: z.array(z.number().min(0)).min(1).max(6) },
        (args) => lookAtClip(ctx, args.moment_id, args.times_s),
      ),
      tool(
        "preview_frames",
        "Bundle the workspace and render stills of your AgentVideo composition at the given frame numbers (up to 6). Returns the images, or the bundle or runtime error as text so you can fix it.",
        { frames: z.array(z.number().int().min(0)).min(1).max(6) },
        (args) => previewFrames(ctx, args.frames),
      ),
      tool(
        "render_video",
        `Render the whole composition to the final MP4 and report its duration, size and fps (ffprobe). At most ${ctx.maxRenders} per job, so preview first.`,
        {},
        () => renderVideo(ctx),
      ),
      tool(
        "submit",
        "Submit what is in the latest render: total_s (its duration), the title shown, and one entry per clip used in playback order with the output seconds it is on screen. Returns the broken rules if it is not accepted.",
        {
          total_s: z.number(),
          title: z.object({ text: z.string(), subtitle: z.string().nullable() }),
          moments: z.array(z.object({ moment_id: z.string(), start_s: z.number(), end_s: z.number() })),
        },
        async (args) => submit(ctx, args),
      ),
    ],
  });
}

/** Bundles the workspace if src/ changed since the last bundle, then selects AgentVideo with the preset's output. */
async function prepare(ctx: ToolContext) {
  const key = hashDir(ctx.ws.srcDir);
  let current = ctx.session.bundle;
  if (current?.key !== key) {
    if (current) fs.rmSync(path.dirname(current.serveUrl), { recursive: true, force: true });
    const outDir = path.join(ctx.ws.bundleDir, key, "site");
    const serveUrl = await bundle({
      entryPoint: ctx.ws.entry,
      publicDir: ctx.ws.publicDir,
      symlinkPublicDir: true,
      outDir,
      webpackOverride: (config) => ({
        ...config,
        resolve: {
          ...config.resolve,
          // `@roamory/...` is render/src/remotion; packages resolve from render/node_modules wherever AGENT_WORK_DIR is.
          alias: { ...(config.resolve?.alias as Record<string, string> | undefined), "@roamory": path.join(RENDER_ROOT, "src/remotion") },
          modules: [...(config.resolve?.modules ?? ["node_modules"]), path.join(RENDER_ROOT, "node_modules")],
        },
      }),
    });
    current = ctx.session.bundle = { key, serveUrl };
  }
  const inputProps = { output: ctx.input.preset.output };
  const composition = await selectComposition({ serveUrl: current.serveUrl, id: COMPOSITION, inputProps, port: await freePort(), logLevel: "error" });
  return { serveUrl: current.serveUrl, composition, inputProps };
}

/** Hash of every file under dir (names and contents). */
function hashDir(dir: string): string {
  const hash = createHash("sha256");
  const walk = (d: string) => {
    for (const entry of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const p = path.join(d, entry.name);
      if (entry.isDirectory()) walk(p);
      else if (entry.isFile()) hash.update(path.relative(dir, p)).update("\0").update(fs.readFileSync(p)).update("\0");
    }
  };
  walk(dir);
  return hash.digest("hex").slice(0, 16);
}

/** A Remotion cancel signal that fires when the job's signal aborts. */
function cancelOn(signal: AbortSignal) {
  const { cancelSignal, cancel } = makeCancelSignal();
  if (signal.aborted) cancel();
  signal.addEventListener("abort", cancel);
  return { cancelSignal, dispose: () => signal.removeEventListener("abort", cancel) };
}
