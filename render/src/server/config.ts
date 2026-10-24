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
  agent: AgentConfig;
};

/** Agent mode (POST /v1/agent, TRD §9.3). */
export type AgentConfig = {
  model: string;
  effort: "low" | "medium" | "high" | "xhigh" | "max";
  maxTurns: number;
  /** The job fails with agent_timeout after this. */
  timeoutS: number;
  /** render_video calls per job. */
  maxRenders: number;
  /** Agent jobs per trip_id while the server runs; more get 429 rate_limited. */
  perTrip: number;
  /** Per-job workspaces. Inside render/ so the agent's code resolves render/node_modules; emptied at startup. */
  workRoot: string;
};

const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;

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
    agent: {
      model: env.AGENT_MODEL || "claude-opus-5-5",
      effort: effort(env.AGENT_EFFORT || "high"),
      maxTurns: num("AGENT_MAX_TURNS", 60),
      timeoutS: num("AGENT_TIMEOUT_S", 480),
      maxRenders: num("AGENT_MAX_RENDERS", 3),
      perTrip: num("AGENTS_PER_TRIP", 3),
      workRoot: path.resolve(RENDER_ROOT, env.AGENT_WORK_DIR || ".agent-work"),
    },
  };
}

function effort(value: string): AgentConfig["effort"] {
  if (!(EFFORTS as readonly string[]).includes(value)) throw new Error(`AGENT_EFFORT must be one of ${EFFORTS.join(", ")}`);
  return value as AgentConfig["effort"];
}
