import { randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import type { AgentInput, AgentResult } from "../agent/types";

export type JobStatus = "queued" | "rendering" | "completed" | "failed";
export type JobError = { code: string; message: string; retryable: boolean };

/** contracts/render_job.schema.json */
export type JobView = { job_id: string; status: JobStatus; progress: number; error: JobError | null };

/**
 * Runs agent mode: reads `{workDir}/clips/`, leaves the video at `{workDir}/out.mp4` and returns what is in it.
 * Must stop soon after `signal` aborts. The real one is src/agent/run.ts; tests pass a fake.
 */
export type AgentFn = (
  input: AgentInput,
  workDir: string,
  onProgress: (progress: number) => void,
  signal: AbortSignal,
) => Promise<AgentResult>;

type Job = JobView & { dir: string; endedAt: number | null; result: AgentResult | null };

/** A slot held for an upload in progress. The upload is written to clipsDir. */
export type Reservation = { id: string; dir: string; clipsDir: string };

/** How long an agent may take to stop after its timeout before the job fails anyway. */
const AGENT_STOP_GRACE_MS = 30_000;

export type JobsOptions = {
  root: string;
  concurrency: number;
  ttlS: number;
  /** Without it every job fails. */
  agent?: AgentFn;
  /** Seconds before an agent job is aborted and fails with agent_timeout. */
  agentTimeoutS?: number;
  now?: () => number;
  log?: (line: string) => void;
};

/**
 * Agent job state in memory, one dir per job under `root` (clips/ and out.mp4).
 * Retention (contracts README): clips go when the job ends; the output after download or `ttlS` after it ends.
 */
export class Jobs {
  private jobs = new Map<string, Job>();
  private reserved = 0;
  private readonly now: () => number;
  private readonly log: (line: string) => void;

  constructor(private readonly opts: JobsOptions) {
    this.now = opts.now ?? Date.now;
    this.log = opts.log ?? ((line) => console.log(line));
    // Anything left from a previous run is unreachable now.
    fs.rmSync(opts.root, { recursive: true, force: true });
    fs.mkdirSync(opts.root, { recursive: true });
  }

  /** Jobs uploading, queued or rendering. */
  get active(): number {
    return this.reserved + [...this.jobs.values()].filter((j) => j.status === "queued" || j.status === "rendering").length;
  }

  /** Holds a slot for an upload, or null when RENDER_CONCURRENCY jobs are already active (429 busy). */
  reserve(): Reservation | null {
    if (this.active >= this.opts.concurrency) return null;
    this.reserved++;
    const id = `a_${randomBytes(12).toString("hex")}`;
    const dir = path.join(this.opts.root, id);
    const clipsDir = path.join(dir, "clips");
    fs.mkdirSync(clipsDir, { recursive: true });
    return { id, dir, clipsDir };
  }

  /** Gives back a slot whose upload was rejected, and deletes what was uploaded. */
  cancel(r: Reservation): void {
    this.reserved--;
    fs.rmSync(r.dir, { recursive: true, force: true });
  }

  /** Turns a reservation into an agent job and starts it. */
  startAgent(r: Reservation, input: Omit<AgentInput, "jobId">): JobView {
    const job = this.add(r);
    void this.runAgent(job, { ...input, jobId: job.job_id });
    return this.view(job);
  }

  get(id: string): JobView | null {
    const job = this.jobs.get(id);
    return job ? this.view(job) : null;
  }

  /** Path of a completed job's video, or null. */
  videoPath(id: string): string | null {
    const job = this.jobs.get(id);
    return job?.status === "completed" ? path.join(job.dir, "out.mp4") : null;
  }

  /** What a completed job put in its video, or null. */
  result(id: string): AgentResult | null {
    const job = this.jobs.get(id);
    return job?.status === "completed" ? job.result : null;
  }

  /** Forgets a job and deletes its dir (after download, or on TTL). */
  delete(id: string): void {
    const job = this.jobs.get(id);
    if (!job) return;
    this.jobs.delete(id);
    fs.rmSync(job.dir, { recursive: true, force: true });
  }

  /** Deletes jobs that ended more than ttlS ago. Returns how many. */
  sweep(): number {
    const cutoff = this.now() - this.opts.ttlS * 1000;
    const expired = [...this.jobs.values()].filter((j) => j.endedAt !== null && j.endedAt <= cutoff);
    for (const job of expired) {
      this.log(`agent job=${job.job_id} expired status=${job.status}`);
      this.delete(job.job_id);
    }
    return expired.length;
  }

  private add(r: Reservation): Job {
    this.reserved--;
    const job: Job = { job_id: r.id, status: "queued", progress: 0, error: null, dir: r.dir, endedAt: null, result: null };
    this.jobs.set(r.id, job);
    return job;
  }

  private progress(job: Job): (p: number) => void {
    return (p) => {
      job.progress = Math.min(1, Math.max(job.progress, p));
    };
  }

  /** Marks a job ended and deletes its uploaded clips. The job may already be gone (deleted while running); rmSync with force copes. */
  private end(job: Job): void {
    job.endedAt = this.now();
    fs.rmSync(path.join(job.dir, "clips"), { recursive: true, force: true });
  }

  private view(job: Job): JobView {
    return { job_id: job.job_id, status: job.status, progress: job.progress, error: job.error };
  }

  /**
   * Runs the agent under AGENT_TIMEOUT_S. On timeout it aborts the agent and waits for it to stop,
   * up to a grace period, so the slot isn't freed while its Chrome still renders.
   */
  private async runAgent(job: Job, input: AgentInput): Promise<void> {
    const started = this.now();
    const controller = new AbortController();
    let timedOut = false;
    let grace: NodeJS.Timeout | undefined;
    const gaveUp = new Promise<never>((_, reject) => {
      controller.signal.addEventListener("abort", () => {
        grace = setTimeout(() => reject(new Error("agent did not stop after its timeout")), AGENT_STOP_GRACE_MS);
      });
    });
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
    }, (this.opts.agentTimeoutS ?? 480) * 1000);
    job.status = "rendering";
    try {
      if (!this.opts.agent) throw new Error("agent mode is not configured");
      const result = await Promise.race([this.opts.agent(input, job.dir, this.progress(job), controller.signal), gaveUp]);
      if (timedOut) throw new Error("timed out");
      if (!fs.existsSync(path.join(job.dir, "out.mp4"))) throw new Error("the agent left no video");
      job.result = result;
      job.status = "completed";
      job.progress = 1;
    } catch (e) {
      job.status = "failed";
      job.error = timedOut
        ? { code: "agent_timeout", message: `agent ran past ${this.opts.agentTimeoutS ?? 480} s`, retryable: false }
        : { code: "agent_failed", message: e instanceof Error ? e.message : String(e), retryable: false };
    } finally {
      clearTimeout(timer);
      clearTimeout(grace);
    }
    this.end(job);
    const elapsed = ((job.endedAt! - started) / 1000).toFixed(1);
    this.log(`agent job=${job.job_id} ${job.status} clips=${input.request.clips.length} style=${input.request.style} elapsed_s=${elapsed}${job.error ? ` error=${job.error.code}` : ""}`);
  }
}
