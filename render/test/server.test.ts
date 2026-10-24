import fs from "node:fs";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import type { AgentInput, AgentRequest, AgentResult } from "../src/agent/types";
import type { HighlightProps, RenderRequest } from "../src/remotion/types";
import type { Config } from "../src/server/config";
import { createApp } from "../src/server/index";
import { Jobs, type AgentFn, type JobView, type RenderFn } from "../src/server/jobs";
import { validateRenderJob } from "../src/server/validate";
import { presets } from "../src/server/validateAgent";
import { agentRequest, agentResult, renderRequest } from "./helpers";

const TOKEN = "test-token";
const VIDEO = Buffer.from("fake mp4 bytes");

/** A renderer the test drives: it reports progress, then waits for finish() or fail(). */
function fakeRenderer() {
  const calls: { props: HighlightProps; outputPath: string }[] = [];
  let settle: { finish: () => void; fail: (e: Error) => void } | null = null;
  const render: RenderFn = (props, outputPath, onProgress) => {
    calls.push({ props, outputPath });
    onProgress(0.5);
    return new Promise((resolve, reject) => {
      settle = {
        finish: () => {
          fs.writeFileSync(outputPath, VIDEO);
          resolve();
        },
        fail: reject,
      };
    });
  };
  return { render, calls, finish: () => settle!.finish(), fail: (e: Error) => settle!.fail(e) };
}

/** An agent the test drives, like fakeRenderer. It stops (rejects) when its signal aborts. */
function fakeAgent() {
  const calls: { input: AgentInput; workDir: string; clips: string[] }[] = [];
  let settle: { finish: (r?: AgentResult, video?: boolean) => void; fail: (e: Error) => void } | null = null;
  const agent: AgentFn = (input, workDir, onProgress, signal) => {
    calls.push({ input, workDir, clips: fs.readdirSync(path.join(workDir, "clips")).sort() });
    onProgress(0.3);
    return new Promise((resolve, reject) => {
      signal.addEventListener("abort", () => reject(new Error("aborted")));
      settle = {
        finish: (r = agentResult(), video = true) => {
          if (video) fs.writeFileSync(path.join(workDir, "out.mp4"), VIDEO);
          resolve(r);
        },
        fail: reject,
      };
    });
  };
  return {
    agent,
    calls,
    finish: (r?: AgentResult, video?: boolean) => settle!.finish(r, video),
    fail: (e: Error) => settle!.fail(e),
  };
}

type Harness = Awaited<ReturnType<typeof start>>;
let current: Harness | null = null;

async function start(overrides: Partial<Config> = {}) {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), "roamory-render-test-"));
  const config: Config = {
    appToken: TOKEN,
    port: 0,
    concurrency: 1,
    ttlS: 900,
    maxUploadBytes: 10 * 1024 * 1024,
    tmpRoot: path.join(tmpRoot, "jobs"),
    publicDir: path.join(tmpRoot, "public"),
    agent: {
      model: "test",
      effort: "high",
      maxTurns: 60,
      timeoutS: 480,
      maxRenders: 3,
      perTrip: 3,
      workRoot: path.join(tmpRoot, "agent-work"),
    },
    ...overrides,
  };
  const renderer = fakeRenderer();
  const agent = fakeAgent();
  let now = 1_000_000;
  let port = 0;
  const jobs = new Jobs({
    root: config.tmpRoot,
    concurrency: config.concurrency,
    ttlS: config.ttlS,
    render: renderer.render,
    agent: agent.agent,
    agentTimeoutS: config.agent.timeoutS,
    clipUrl: (id, momentId) => `http://127.0.0.1:${port}/internal/clips/${id}/${momentId}.mp4`,
    musicSrc: () => null,
    now: () => now,
    log: () => {},
  });
  const server: Server = await new Promise((resolve) => {
    const s = createApp(config, jobs).listen(0, "127.0.0.1", () => resolve(s));
  });
  port = (server.address() as AddressInfo).port;
  const base = `http://127.0.0.1:${port}`;
  const harness = {
    config,
    jobs,
    renderer,
    agent,
    base,
    advance: (ms: number) => {
      now += ms;
    },
    get: (p: string, token: string | null = TOKEN) =>
      fetch(base + p, { headers: token ? { authorization: `Bearer ${token}` } : {} }),
    post: (body: FormData, token: string | null = TOKEN, route = "/v1/render") =>
      fetch(`${base}${route}`, { method: "POST", body, headers: token ? { authorization: `Bearer ${token}` } : {} }),
    postAgent: (body: FormData) => harness.post(body, TOKEN, "/v1/agent"),
    close: () => new Promise<void>((resolve) => server.close(() => resolve())),
    tmpRoot,
  };
  current = harness;
  return harness;
}

afterEach(async () => {
  await current?.close();
  if (current) fs.rmSync(current.tmpRoot, { recursive: true, force: true });
  current = null;
});

/** Like the phone: `request` as a plain field, one {moment_id}.mp4 file part per clip. */
function form(request: RenderRequest | string = renderRequest("reels"), clipNames?: string[], requestAsFile = false): FormData {
  const body = new FormData();
  const json = typeof request === "string" ? request : JSON.stringify(request);
  if (requestAsFile) body.append("request", new Blob([json], { type: "application/json" }), "request.json");
  else body.append("request", json);
  const names = clipNames ?? (typeof request === "string" ? [] : request.clips.map((c) => `${c.moment_id}.mp4`));
  for (const name of names) body.append(name, new Blob([`clip ${name}`], { type: "video/mp4" }), name);
  return body;
}

/** An agent request with one {moment_id}.mp4 part per clip. */
function agentForm(request: AgentRequest | string = agentRequest("reels"), clipNames?: string[]): FormData {
  const body = new FormData();
  body.append("request", typeof request === "string" ? request : JSON.stringify(request));
  const names = clipNames ?? (typeof request === "string" ? [] : request.clips.map((c) => `${c.moment_id}.mp4`));
  for (const name of names) body.append(name, new Blob([`clip ${name}`], { type: "video/mp4" }), name);
  return body;
}

async function until(h: Harness, id: string, status: JobView["status"], route = "/v1/render"): Promise<JobView> {
  for (let i = 0; i < 100; i++) {
    const job = (await (await h.get(`${route}/${id}`)).json()) as JobView;
    if (job.status === status) return job;
    await new Promise((r) => setTimeout(r, 10));
  }
  throw new Error(`job ${id} never reached ${status}`);
}

const jobDirs = (h: Harness) => fs.readdirSync(h.config.tmpRoot);

describe("auth", () => {
  it("leaves /healthz open", async () => {
    const h = await start();
    expect((await h.get("/healthz", null)).status).toBe(200);
  });

  it("rejects a missing or wrong token with 401 unauthorized", async () => {
    const h = await start();
    for (const token of [null, "wrong"]) {
      const res = await h.post(form(), token);
      expect(res.status).toBe(401);
      expect(await res.json()).toEqual({ code: "unauthorized", message: expect.any(String), retryable: false });
      expect((await h.get("/v1/render/r_x", token)).status).toBe(401);
    }
  });

  it("rejects everything when APP_TOKEN is unset", async () => {
    const h = await start({ appToken: "" });
    expect((await h.post(form(), "")).status).toBe(401);
  });
});

describe("job lifecycle", () => {
  it("renders, serves the video once, then deletes the job", async () => {
    const h = await start();
    const res = await h.post(form());
    expect(res.status).toBe(202);
    const { job_id } = (await res.json()) as { job_id: string };

    const rendering = await until(h, job_id, "rendering");
    expect(rendering).toEqual({ job_id, status: "rendering", progress: 0.5, error: null });
    expect(validateRenderJob(rendering)).toBe(true);
    expect((await h.get(`/v1/render/${job_id}/video`)).status).toBe(404);

    // The renderer gets each clip from the localhost route while the job runs.
    const { props } = h.renderer.calls[0];
    const first = renderRequest("reels").clips[0];
    expect(props.clips[first.moment_id].has_audio).toBe(first.has_audio);
    const clip = await fetch(props.clips[first.moment_id].src);
    expect(await clip.text()).toBe(`clip ${first.moment_id}.mp4`);
    expect(props.music_src).toBeNull();

    h.renderer.finish();
    const done = await until(h, job_id, "completed");
    expect(done).toEqual({ job_id, status: "completed", progress: 1, error: null });
    expect(validateRenderJob(done)).toBe(true);
    // Clips are deleted when the job ends.
    expect((await fetch(props.clips[first.moment_id].src)).status).toBe(404);
    expect(fs.existsSync(path.join(h.config.tmpRoot, job_id, "clips"))).toBe(false);

    const video = await h.get(`/v1/render/${job_id}/video`);
    expect(video.status).toBe(200);
    expect(video.headers.get("content-type")).toMatch(/video\/mp4/);
    expect(Buffer.from(await video.arrayBuffer())).toEqual(VIDEO);

    await new Promise((r) => setTimeout(r, 20));
    expect(jobDirs(h)).toEqual([]);
    expect((await h.get(`/v1/render/${job_id}`)).status).toBe(404);
    expect((await h.get(`/v1/render/${job_id}/video`)).status).toBe(404);
  });

  it("also takes the request as a file part, as curl -F request=@file.json sends it", async () => {
    const h = await start();
    const res = await h.post(form(renderRequest("reels"), undefined, true));
    expect(res.status).toBe(202);
    await until(h, ((await res.json()) as { job_id: string }).job_id, "rendering");
    expect(Object.keys(h.renderer.calls[0].props.clips)).toHaveLength(renderRequest("reels").clips.length);
  });

  it("reports a failed render as render_failed and keeps no clips", async () => {
    const h = await start();
    const { job_id } = (await (await h.post(form())).json()) as { job_id: string };
    await until(h, job_id, "rendering");
    h.renderer.fail(new Error("Chrome exited"));
    const job = await until(h, job_id, "failed");
    expect(job.error).toEqual({ code: "render_failed", message: "Chrome exited", retryable: false });
    expect(validateRenderJob(job)).toBe(true);
    expect((await h.get(`/v1/render/${job_id}/video`)).status).toBe(404);
    expect(fs.readdirSync(path.join(h.config.tmpRoot, job_id))).toEqual([]);
  });

  it("returns 404 not_found for an unknown job", async () => {
    const h = await start();
    const res = await h.get("/v1/render/r_nope");
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ code: "not_found", retryable: false });
  });

  it("sweeps finished jobs after RENDER_TTL_S", async () => {
    const h = await start({ ttlS: 60 });
    const { job_id } = (await (await h.post(form())).json()) as { job_id: string };
    await until(h, job_id, "rendering");
    h.renderer.finish();
    await until(h, job_id, "completed");
    h.advance(59_000);
    expect(h.jobs.sweep()).toBe(0);
    h.advance(1_000);
    expect(h.jobs.sweep()).toBe(1);
    expect(jobDirs(h)).toEqual([]);
    expect((await h.get(`/v1/render/${job_id}`)).status).toBe(404);
  });
});

describe("limits", () => {
  it("returns 429 busy while RENDER_CONCURRENCY jobs are rendering, and frees the slot after", async () => {
    const h = await start();
    const { job_id } = (await (await h.post(form())).json()) as { job_id: string };
    const busy = await h.post(form());
    expect(busy.status).toBe(429);
    expect(await busy.json()).toMatchObject({ code: "busy", retryable: true });
    expect(jobDirs(h)).toEqual([job_id]);

    await until(h, job_id, "rendering");
    h.renderer.finish();
    await until(h, job_id, "completed");
    expect((await h.post(form())).status).toBe(202);
  });

  it("returns 413 upload_too_large over MAX_UPLOAD_MB", async () => {
    const h = await start({ maxUploadBytes: 64 });
    const res = await h.post(form());
    expect(res.status).toBe(413);
    expect(await res.json()).toMatchObject({ code: "upload_too_large", retryable: false });
    expect(jobDirs(h)).toEqual([]);
  });
});

describe("bad requests", () => {
  it.each([
    [
      "no request part",
      () => {
        const body = new FormData();
        body.append("m_01.mp4", new Blob(["clip"]), "m_01.mp4");
        return body;
      },
    ],
    ["a request that breaks the schema", () => form("{}", [])],
    ["request not JSON", () => form("{nope")],
    ["a clip part missing", () => form(renderRequest("reels"), ["m_01.mp4"])],
    [
      "a trim past the uploaded file",
      () => {
        const r = renderRequest("reels");
        r.edit_spec.clips[0].out_s = 99;
        return form(r);
      },
    ],
  ])("returns 400 bad_request for %s and frees the slot", async (_name, body) => {
    const h = await start();
    const res = await h.post(body());
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ code: "bad_request", retryable: false });
    expect(jobDirs(h)).toEqual([]);
    expect((await h.post(form())).status).toBe(202);
  });
});

describe("internal clip route", () => {
  it("serves nothing for unknown jobs or odd names", async () => {
    const h = await start();
    expect((await fetch(`${h.base}/internal/clips/r_nope/m_01.mp4`)).status).toBe(404);
    expect((await fetch(`${h.base}/internal/clips/r_nope/..%2F..%2Fetc%2Fpasswd`)).status).toBe(404);
  });
});

describe("agent mode", () => {
  const untilAgent = (h: Harness, id: string, status: JobView["status"]) => until(h, id, status, "/v1/agent");
  const startAgent = async (h: Harness, body = agentForm()) => {
    const res = await h.postAgent(body);
    expect(res.status).toBe(202);
    return ((await res.json()) as { job_id: string }).job_id;
  };

  it("runs the agent, serves the result and the video once, then deletes the job", async () => {
    const h = await start();
    const job_id = await startAgent(h);
    const running = await untilAgent(h, job_id, "rendering");
    expect(running).toEqual({ job_id, status: "rendering", progress: 0.3, error: null });
    expect(validateRenderJob(running)).toBe(true);
    // Agent and render jobs don't share ids.
    expect((await h.get(`/v1/render/${job_id}`)).status).toBe(404);
    expect((await h.get(`/v1/agent/${job_id}/result`)).status).toBe(404);
    expect((await h.get(`/v1/agent/${job_id}/video`)).status).toBe(404);

    // The agent gets the request, its style's preset and every uploaded clip.
    const request = agentRequest("reels");
    const { input, clips } = h.agent.calls[0];
    expect(input).toEqual({ jobId: job_id, request, preset: presets.reels });
    expect(clips).toEqual(request.clips.map((c) => `${c.moment_id}.mp4`).sort());

    h.agent.finish();
    expect(await untilAgent(h, job_id, "completed")).toEqual({ job_id, status: "completed", progress: 1, error: null });
    expect(fs.existsSync(path.join(h.config.tmpRoot, job_id, "clips"))).toBe(false);
    const result = await h.get(`/v1/agent/${job_id}/result`);
    expect(result.status).toBe(200);
    expect(await result.json()).toEqual(agentResult());

    const video = await h.get(`/v1/agent/${job_id}/video`);
    expect(video.status).toBe(200);
    expect(Buffer.from(await video.arrayBuffer())).toEqual(VIDEO);
    await new Promise((r) => setTimeout(r, 20));
    expect(jobDirs(h)).toEqual([]);
    expect((await h.get(`/v1/agent/${job_id}`)).status).toBe(404);
    expect((await h.get(`/v1/agent/${job_id}/result`)).status).toBe(404);
  });

  it("reports an agent error as agent_failed", async () => {
    const h = await start();
    const job_id = await startAgent(h);
    await untilAgent(h, job_id, "rendering");
    h.agent.fail(new Error("the agent ended without a valid submit"));
    const job = await untilAgent(h, job_id, "failed");
    expect(job.error).toEqual({ code: "agent_failed", message: "the agent ended without a valid submit", retryable: false });
    expect(validateRenderJob(job)).toBe(true);
    expect((await h.get(`/v1/agent/${job_id}/result`)).status).toBe(404);
    expect(fs.readdirSync(path.join(h.config.tmpRoot, job_id))).toEqual([]);
  });

  it("fails with agent_failed when the agent returns without a video", async () => {
    const h = await start();
    const job_id = await startAgent(h);
    await untilAgent(h, job_id, "rendering");
    h.agent.finish(agentResult(), false);
    const job = await untilAgent(h, job_id, "failed");
    expect(job.error?.code).toBe("agent_failed");
  });

  it("aborts the agent at AGENT_TIMEOUT_S and reports agent_timeout", async () => {
    const h = await start();
    const jobs = new Jobs({
      root: path.join(h.tmpRoot, "timeout-jobs"),
      concurrency: 1,
      ttlS: 900,
      render: h.renderer.render,
      agent: h.agent.agent,
      agentTimeoutS: 0.05,
      clipUrl: () => "",
      musicSrc: () => null,
      log: () => {},
    });
    const r = jobs.reserve("agent")!;
    const { job_id } = jobs.startAgent(r, { request: agentRequest("reels"), preset: presets.reels });
    for (let i = 0; i < 50 && jobs.get(job_id, "agent")!.status !== "failed"; i++) await new Promise((res) => setTimeout(res, 10));
    expect(jobs.get(job_id, "agent")!.error).toEqual({ code: "agent_timeout", message: "agent ran past 0.05 s", retryable: false });
    expect(jobs.active).toBe(0);
  });

  it("shares the slots with /v1/render: 429 busy either way", async () => {
    const h = await start();
    const { job_id } = (await (await h.post(form())).json()) as { job_id: string };
    const busy = await h.postAgent(agentForm());
    expect(busy.status).toBe(429);
    expect(await busy.json()).toMatchObject({ code: "busy", retryable: true });
    await until(h, job_id, "rendering");
    h.renderer.finish();
    await until(h, job_id, "completed");

    const agentJob = await startAgent(h);
    expect((await h.post(form())).status).toBe(429);
    await untilAgent(h, agentJob, "rendering");
    h.agent.finish();
    await untilAgent(h, agentJob, "completed");
    expect((await h.post(form())).status).toBe(202);
  });

  it("returns 429 rate_limited past AGENTS_PER_TRIP for one trip", async () => {
    const h = await start();
    h.config.agent.perTrip = 1;
    const first = await startAgent(h);
    await untilAgent(h, first, "rendering");
    h.agent.finish();
    await untilAgent(h, first, "completed");
    const again = await h.postAgent(agentForm());
    expect(again.status).toBe(429);
    expect(await again.json()).toMatchObject({ code: "rate_limited", retryable: false });
    expect(jobDirs(h)).toEqual([first]);
    // Another trip still gets one.
    expect((await h.postAgent(agentForm({ ...agentRequest("reels"), trip_id: "t_other" }))).status).toBe(202);
  });

  it.each([
    ["a request that breaks the schema", () => agentForm("{}", [])],
    ["a render request", () => agentForm(JSON.stringify(renderRequest("reels")), [])],
    ["a clip part missing", () => agentForm(agentRequest("reels"), ["m_01.mp4"])],
    [
      "a proposed trim past the uploaded file",
      () => {
        const r = agentRequest("reels");
        r.clips[0].proposed_out_s = 99;
        return agentForm(r);
      },
    ],
  ])("returns 400 bad_request for %s and frees the slot", async (_name, body) => {
    const h = await start();
    const res = await h.postAgent(body());
    expect(res.status).toBe(400);
    expect(await res.json()).toMatchObject({ code: "bad_request", retryable: false });
    expect(jobDirs(h)).toEqual([]);
    expect((await h.postAgent(agentForm())).status).toBe(202);
  });

  it("needs the bearer token", async () => {
    const h = await start();
    expect((await h.post(agentForm(), null, "/v1/agent")).status).toBe(401);
    expect((await h.get("/v1/agent/a_x", null)).status).toBe(401);
  });
});
