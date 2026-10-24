import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

/** Long side of the JPEGs look_at_clip returns. */
const FRAME_PX = 384;

/** One frame of a video at `t` seconds as a JPEG, long side FRAME_PX. Needs ffmpeg on PATH. */
export async function extractFrame(file: string, t: number, signal?: AbortSignal): Promise<Buffer> {
  const scale = `scale='if(gte(iw,ih),${FRAME_PX},-2)':'if(gte(iw,ih),-2,${FRAME_PX})'`;
  const { stdout } = await run(
    "ffmpeg",
    ["-v", "error", "-ss", t.toFixed(3), "-i", file, "-frames:v", "1", "-vf", scale, "-q:v", "4", "-f", "image2pipe", "-c:v", "mjpeg", "pipe:1"],
    { encoding: "buffer", maxBuffer: 16 * 1024 * 1024, signal },
  );
  if (stdout.length === 0) throw new Error(`no frame at ${t} s`);
  return stdout;
}

export type Probe = { duration_s: number; width: number; height: number; fps: number; size_bytes: number };

/** Duration, size and frame rate of a video. Needs ffprobe on PATH. */
export async function probe(file: string): Promise<Probe> {
  const { stdout } = await run("ffprobe", [
    "-v", "error",
    "-select_streams", "v:0",
    "-show_entries", "stream=width,height,r_frame_rate:format=duration,size",
    "-of", "json",
    file,
  ]);
  const info = JSON.parse(stdout) as {
    streams: { width: number; height: number; r_frame_rate: string }[];
    format: { duration: string; size: string };
  };
  const stream = info.streams[0];
  if (!stream) throw new Error("no video stream");
  const [n, d] = stream.r_frame_rate.split("/").map(Number);
  return {
    duration_s: Number(info.format.duration),
    width: stream.width,
    height: stream.height,
    fps: d ? n / d : n,
    size_bytes: Number(info.format.size),
  };
}
