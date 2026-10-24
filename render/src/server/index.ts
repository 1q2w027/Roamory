import { timingSafeEqual } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import express, { type ErrorRequestHandler, type RequestHandler, type Response } from "express";
import multer from "multer";
import { loadConfig, type Config } from "./config";
import { Jobs, type AgentFn, type Reservation } from "./jobs";
import { presets, validateAgentRequestParts } from "./validate";

type Upload = { reservation: Reservation; raw: string | undefined; clipParts: string[] };

/** Error body (contracts/error.schema.json). */
function fail(res: Response, status: number, code: string, message: string, retryable = false) {
  res.status(status).json({ code, message, retryable });
}

export function createApp(config: Config, jobs: Jobs) {
  const app = express();
  app.disable("x-powered-by");

  app.get("/healthz", (_req, res) => {
    res.json({ ok: true, active: jobs.active });
  });

  // Bearer APP_TOKEN (contracts README, Auth). An unset token rejects everything, like the backend.
  const expected = Buffer.from(`Bearer ${config.appToken}`);
  const auth: RequestHandler = (req, res, next) => {
    const given = Buffer.from(req.get("authorization") ?? "");
    if (!config.appToken || given.length !== expected.length || !timingSafeEqual(given, expected)) {
      return fail(res, 401, "unauthorized", "missing or wrong bearer token");
    }
    next();
  };
  app.use("/v1", auth);

  const upload = multer({
    storage: multer.diskStorage({
      destination: (req, _file, cb) => cb(null, (req as { reservation?: Reservation }).reservation!.clipsDir),
      // validate.ts rejects any name that isn't a clip's {moment_id}.mp4; this only keeps paths inside the dir.
      filename: (_req, file, cb) => cb(null, path.basename(file.fieldname)),
    }),
    limits: { fileSize: config.maxUploadBytes, fieldSize: 1024 * 1024, fields: 4, files: 200 },
  });

  /**
   * Holds a slot, then takes the multipart upload into its clips dir: 413 over MAX_UPLOAD_MB,
   * 429 busy with no slot. Leaves `request` and the clip part names on `req.upload`; the slot is the
   * route's to start or cancel from then on.
   */
  const receive: RequestHandler[] = [
    (req, res, next) => {
      if (Number(req.get("content-length") ?? 0) > config.maxUploadBytes) {
        return fail(res, 413, "upload_too_large", `upload is over ${config.maxUploadBytes} bytes`);
      }
      // Hold a slot before reading the upload, so a busy server doesn't take 30 MB it will drop.
      const reservation = jobs.reserve();
      if (!reservation) return fail(res, 429, "busy", "an agent job is already running", true);
      (req as { reservation?: Reservation }).reservation = reservation;
      upload.any()(req, res, (err?: unknown) => {
        if (!err) return next();
        jobs.cancel(reservation);
        if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
          return fail(res, 413, "upload_too_large", `a clip is over ${config.maxUploadBytes} bytes`);
        }
        fail(res, 400, "bad_request", err instanceof Error ? err.message : "bad upload");
      });
    },
    (req, res, next) => {
      const reservation = (req as { reservation?: Reservation }).reservation!;
      const files = (req.files as Express.Multer.File[] | undefined) ?? [];
      const total = files.reduce((sum, f) => sum + f.size, 0);
      if (total > config.maxUploadBytes) {
        jobs.cancel(reservation);
        return fail(res, 413, "upload_too_large", `upload is over ${config.maxUploadBytes} bytes`);
      }
      // The phone sends `request` as a field; `curl -F request=@file.json` sends it as a file.
      const requestFile = files.find((f) => f.fieldname === "request");
      const raw: string | undefined = requestFile ? fs.readFileSync(requestFile.path, "utf8") : req.body?.request;
      if (requestFile) fs.rmSync(requestFile.path);
      const clipParts = files.filter((f) => f !== requestFile).map((f) => f.fieldname);
      (req as { upload?: Upload }).upload = { reservation, raw, clipParts };
      next();
    },
  ];
  const uploaded = (req: express.Request) => (req as { upload?: Upload }).upload!;

  // Agent mode (contracts README, "Agent mode: /v1/agent"). Agent jobs per trip, since the server started.
  const agentsByTrip = new Map<string, number>();
  app.post("/v1/agent", ...receive, (req, res) => {
    const { reservation, raw, clipParts } = uploaded(req);
    const result = validateAgentRequestParts(raw, clipParts);
    if (!result.ok) {
      jobs.cancel(reservation);
      return fail(res, 400, "bad_request", result.message);
    }
    const { request } = result;
    const count = agentsByTrip.get(request.trip_id) ?? 0;
    if (count >= config.agent.perTrip) {
      jobs.cancel(reservation);
      return fail(res, 429, "rate_limited", `trip is over ${config.agent.perTrip} agent jobs`);
    }
    agentsByTrip.set(request.trip_id, count + 1);
    const job = jobs.startAgent(reservation, { request, preset: presets[request.style] });
    res.status(202).json({ job_id: job.job_id });
  });

  app.get("/v1/agent/:id", (req, res) => {
    const job = jobs.get(req.params.id);
    if (!job) return fail(res, 404, "not_found", "unknown or deleted job");
    res.json(job);
  });

  app.get("/v1/agent/:id/result", (req, res) => {
    const result = jobs.result(req.params.id);
    if (!result) return fail(res, 404, "not_found", "no result for this job (unknown, not completed, or already downloaded)");
    res.json(result);
  });

  app.get("/v1/agent/:id/video", (req, res) => {
    const file = jobs.videoPath(req.params.id);
    if (!file) return fail(res, 404, "not_found", "no video for this job (unknown, not completed, or already downloaded)");
    res.type("video/mp4").sendFile(file, (err) => {
      // Delete once sent. If the download broke, keep it for a retry until the TTL sweep.
      if (!err) jobs.delete(req.params.id);
    });
  });

  app.use((_req, res) => fail(res, 404, "not_found", "no such route"));

  const onError: ErrorRequestHandler = (err, _req, res, _next) => {
    console.error(`render internal error: ${err instanceof Error ? err.name : "unknown"}`);
    if (res.headersSent) return;
    fail(res, 500, "internal", "internal error", true);
  };
  app.use(onError);
  return app;
}

/** Builds the job store over an agent runner. */
export function createJobs(config: Config, agent?: AgentFn): Jobs {
  return new Jobs({ root: config.tmpRoot, concurrency: config.concurrency, ttlS: config.ttlS, agent, agentTimeoutS: config.agent.timeoutS });
}

async function main() {
  const config = loadConfig();
  if (!config.appToken) console.warn("APP_TOKEN is not set: every /v1 request will get 401");
  if (!process.env.ANTHROPIC_API_KEY) console.warn("ANTHROPIC_API_KEY is not set: every agent job will fail");
  const { createAgentRunner } = await import("../agent/run");
  const jobs = createJobs(config, createAgentRunner(config));
  setInterval(() => jobs.sweep(), Math.min(60, config.ttlS) * 1000).unref();
  createApp(config, jobs).listen(config.port, () => {
    console.log(`render service on :${config.port}`);
    // What a phone on the same network can use (ios/Roamory/Config/use-laptop-render.sh writes the first)
    const lan = Object.values(os.networkInterfaces()).flat().filter((a) => a && a.family === "IPv4" && !a.internal);
    if (process.platform === "darwin") console.log(`  from a phone: http://${os.hostname().replace(/\.local$/, "")}.local:${config.port}`);
    for (const a of lan) console.log(`  from a phone: http://${a!.address}:${config.port}`);
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}
