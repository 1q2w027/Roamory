import { timingSafeEqual } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import type { AddressInfo } from "node:net";
import path from "node:path";
import { pathToFileURL } from "node:url";
import express, { type ErrorRequestHandler, type RequestHandler, type Response } from "express";
import multer from "multer";
import { loadConfig, type Config } from "./config";
import { Jobs, type RenderFn, type Reservation } from "./jobs";
import { validateRequest } from "./validate";

/** Error body (contracts/error.schema.json). */
function fail(res: Response, status: number, code: string, message: string, retryable = false) {
  res.status(status).json({ code, message, retryable });
}

/** Loopback only: the renderer's Chrome and compositor fetch clips from here. */
function isLoopback(address: string | undefined): boolean {
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

export function createApp(config: Config, jobs: Jobs) {
  const app = express();
  app.disable("x-powered-by");

  app.get("/healthz", (_req, res) => {
    res.json({ ok: true, active: jobs.active });
  });

  // Clips for the renderer. Not under /v1, so no token; unreachable except from this machine.
  app.get("/internal/clips/:id/:file", (req, res) => {
    const file = isLoopback(req.socket.remoteAddress) ? jobs.clipPath(req.params.id, req.params.file) : null;
    if (!file || !fs.existsSync(file)) return fail(res, 404, "not_found", "no such clip");
    res.sendFile(file);
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

  app.post(
    "/v1/render",
    (req, res, next) => {
      if (Number(req.get("content-length") ?? 0) > config.maxUploadBytes) {
        return fail(res, 413, "upload_too_large", `upload is over ${config.maxUploadBytes} bytes`);
      }
      // Hold a slot before reading the upload, so a busy server doesn't take 30 MB it will drop.
      const reservation = jobs.reserve();
      if (!reservation) return fail(res, 429, "busy", "already rendering", true);
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
    (req, res) => {
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
      const result = validateRequest(raw, clipParts);
      if (!result.ok) {
        jobs.cancel(reservation);
        return fail(res, 400, "bad_request", result.message);
      }
      const job = jobs.start(reservation, result.request);
      res.status(202).json({ job_id: job.job_id });
    },
  );

  app.get("/v1/render/:id", (req, res) => {
    const job = jobs.get(req.params.id);
    if (!job) return fail(res, 404, "not_found", "unknown or deleted job");
    res.json(job);
  });

  app.get("/v1/render/:id/video", (req, res) => {
    const id = req.params.id;
    const file = jobs.videoPath(id);
    if (!file) return fail(res, 404, "not_found", "no video for this job (unknown, not completed, or already downloaded)");
    res.type("video/mp4").sendFile(file, (err) => {
      // Delete once sent. If the download broke, keep it for a retry until the TTL sweep.
      if (!err) jobs.delete(id);
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

/**
 * Builds the job store over a renderer, with the clip and music lookups the real server uses.
 * `origin()` is this server's loopback origin, known once it listens.
 */
export function createJobs(config: Config, render: RenderFn, origin: () => string): Jobs {
  return new Jobs({
    root: config.tmpRoot,
    concurrency: config.concurrency,
    ttlS: config.ttlS,
    render,
    clipUrl: (id, momentId) => `${origin()}/internal/clips/${id}/${encodeURIComponent(momentId)}.mp4`,
    musicSrc: (track) => {
      const src = `music/${track}.m4a`;
      return /^[A-Za-z0-9_-]+$/.test(track) && fs.existsSync(path.join(config.publicDir, src)) ? src : null;
    },
  });
}

async function main() {
  const config = loadConfig();
  if (!config.appToken) console.warn("APP_TOKEN is not set: every /v1 request will get 401");
  const { createRemotionRenderer } = await import("./renderer");
  let origin = "";
  const jobs = createJobs(config, await createRemotionRenderer(config.publicDir), () => origin);
  setInterval(() => jobs.sweep(), Math.min(60, config.ttlS) * 1000).unref();
  const server = createApp(config, jobs).listen(config.port, () => {
    // Reach ourselves over the family we bound: on a dual-stack bind another process can still
    // hold 127.0.0.1 on the same port, and the renderer would fetch clips from it.
    const { family } = server.address() as AddressInfo;
    origin = `http://${family === "IPv6" ? "[::1]" : "127.0.0.1"}:${config.port}`;
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
