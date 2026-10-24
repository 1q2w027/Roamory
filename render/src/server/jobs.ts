import { randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import type { HighlightProps, RenderRequest } from "../remotion/types";

export type JobStatus = "queued" | "rendering" | "completed" | "failed";
export type JobError = { code: string; message: string; retryable: boolean };

/** contracts/render_job.schema.json */
export type JobView = { job_id: string; status: JobStatus; progress: number; error: JobError | null };

/** Renders props to an MP4 at outputPath. The real one is Remotion (renderer.ts); tests pass a fake. */
export type RenderFn = (props: HighlightProps, outputPath: string, onProgress: (progress: number) => void) => Promise<void>;

type Job = JobView & { dir: string; endedAt: number | null };

/** A slot held for an upload in progress. The upload is written to clipsDir. */
export type Reservation = { id: string; dir: string; clipsDir: string };

export type JobsOptions = {
  root: string;
  concurrency: number;
  ttlS: number;
  render: RenderFn;
  /** URL the renderer fetches a job's clip from (the localhost-only route). */
  clipUrl: (jobId: string, momentId: string) => string;
  /** Path under public/ for a music track, or null if it isn't there. */
  musicSrc: (track: string) => string | null;
  now?: () => number;
  log?: (line: string) => void;
};

/**
 * Job state in memory, one dir per job under `root` (clips/ and out.mp4).
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
    const id = `r_${randomBytes(12).toString("hex")}`;
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

  /** Turns a reservation into a job and starts rendering it. */
  start(r: Reservation, request: RenderRequest): JobView {
    this.reserved--;
    const job: Job = { job_id: r.id, status: "queued", progress: 0, error: null, dir: r.dir, endedAt: null };
    this.jobs.set(r.id, job);
    void this.run(job, request);
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

  /** Path of an uploaded clip while its job is active (for the renderer), or null. */
  clipPath(id: string, file: string): string | null {
    const job = this.jobs.get(id);
    if (!job || job.endedAt !== null || !/^[A-Za-z0-9_.-]+\.mp4$/.test(file)) return null;
    return path.join(job.dir, "clips", file);
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
      this.log(`render job=${job.job_id} expired status=${job.status}`);
      this.delete(job.job_id);
    }
    return expired.length;
  }

  private view(job: Job): JobView {
    return { job_id: job.job_id, status: job.status, progress: job.progress, error: job.error };
  }

  private async run(job: Job, request: RenderRequest): Promise<void> {
    const started = this.now();
    const props: HighlightProps = {
      spec: request.edit_spec,
      context: request.context,
      clips: Object.fromEntries(
        request.clips.map((c) => [c.moment_id, { src: this.opts.clipUrl(job.job_id, c.moment_id), has_audio: c.has_audio }]),
      ),
      music_src: this.opts.musicSrc(request.edit_spec.music.track),
    };
    if (!props.music_src) this.log(`render job=${job.job_id} no music for track=${request.edit_spec.music.track}`);
    job.status = "rendering";
    try {
      await this.opts.render(props, path.join(job.dir, "out.mp4"), (p) => {
        job.progress = Math.min(1, Math.max(job.progress, p));
      });
      job.status = "completed";
      job.progress = 1;
    } catch (e) {
      job.status = "failed";
      job.error = { code: "render_failed", message: e instanceof Error ? e.message : String(e), retryable: false };
    }
    job.endedAt = this.now();
    // The job may already be gone (deleted while rendering); rmSync with force copes.
    fs.rmSync(path.join(job.dir, "clips"), { recursive: true, force: true });
    const elapsed = ((job.endedAt - started) / 1000).toFixed(1);
    this.log(`render job=${job.job_id} ${job.status} clips=${request.clips.length} style=${request.edit_spec.style} elapsed_s=${elapsed}${job.error ? ` error=${job.error.code}` : ""}`);
  }
}
