import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { AgentInput } from "./types";

const TEMPLATE_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "template");

/** One agent job's Remotion project: the agent's cwd. */
export type Workspace = {
  dir: string;
  /** The only place the agent may write. */
  srcDir: string;
  publicDir: string;
  entry: string;
  /** Bundles go here, outside the agent's reach (in the job dir, deleted with it). */
  bundleDir: string;
  /** Path under public/ of the style's music bed, or null if it isn't there. */
  musicSrc: string | null;
};

/**
 * Builds `{root}/{jobId}/`:
 *   manifest.json        the request, the style preset, and each clip's staticFile path
 *   entry.ts, Root.tsx   fixed (template/)
 *   src/Video.tsx        the starter composition the agent replaces
 *   public/clips         symlink to the job's uploaded clips
 *   public/music         symlink to the service's music beds
 */
export function createWorkspace(root: string, input: AgentInput, jobDir: string, musicDir: string): Workspace {
  const dir = path.join(root, input.jobId);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.cpSync(TEMPLATE_DIR, dir, { recursive: true });
  const publicDir = path.join(dir, "public");
  fs.mkdirSync(publicDir);
  fs.symlinkSync(path.join(jobDir, "clips"), path.join(publicDir, "clips"));
  if (fs.existsSync(musicDir)) fs.symlinkSync(musicDir, path.join(publicDir, "music"));

  const { request, preset } = input;
  const track = `music/${preset.music_track}.m4a`;
  const musicSrc = fs.existsSync(path.join(musicDir, `${preset.music_track}.m4a`)) ? track : null;
  const manifest = {
    trip_id: request.trip_id,
    style: request.style,
    target_s: request.target_s,
    effective_target_s: request.effective_target_s,
    context: request.context,
    preset,
    music_src: musicSrc,
    clips: request.clips.map((c) => ({ ...c, src: `clips/${c.moment_id}.mp4` })),
  };
  fs.writeFileSync(path.join(dir, "manifest.json"), JSON.stringify(manifest, null, 2));
  return {
    dir,
    srcDir: path.join(dir, "src"),
    publicDir,
    entry: path.join(dir, "entry.ts"),
    bundleDir: path.join(jobDir, "bundle"),
    musicSrc,
  };
}

export function removeWorkspace(ws: Workspace): void {
  fs.rmSync(ws.dir, { recursive: true, force: true });
  fs.rmSync(ws.bundleDir, { recursive: true, force: true });
}
