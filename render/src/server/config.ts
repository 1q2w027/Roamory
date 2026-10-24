import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const RENDER_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const CONTRACTS_DIR = path.resolve(RENDER_ROOT, "../contracts");

/** Config, not code (CLAUDE.md). Read from the repo-root .env and render/.env; see .env.example. */
export type Config = {
  /** Bearer token the app sends. Empty rejects every request, like the backend. */
  appToken: string;
  port: number;
  concurrency: number;
  /** Seconds a finished job's output is kept if it is never downloaded. */
  ttlS: number;
  maxUploadBytes: number;
  /** Job dirs live under here; it is emptied at startup. */
  tmpRoot: string;
  publicDir: string;
};

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const num = (name: string, fallback: number) => {
    const value = Number(env[name] ?? fallback);
    if (!Number.isFinite(value) || value <= 0) throw new Error(`${name} must be a positive number`);
    return value;
  };
  return {
    appToken: env.APP_TOKEN ?? "",
    port: num("PORT", 3000),
    concurrency: num("RENDER_CONCURRENCY", 1),
    ttlS: num("RENDER_TTL_S", 900),
    maxUploadBytes: num("MAX_UPLOAD_MB", 200) * 1024 * 1024,
    tmpRoot: env.RENDER_TMP_DIR || path.join(os.tmpdir(), "roamory-render"),
    publicDir: path.join(RENDER_ROOT, "public"),
  };
}
