import path from "node:path";
import { bundle } from "@remotion/bundler";
import { ensureBrowser, renderMedia, selectComposition } from "@remotion/renderer";
import { RENDER_ROOT } from "./config";
import type { RenderFn } from "./jobs";

/** Bundles the Remotion project once and returns a RenderFn that renders the Highlight composition. */
export async function createRemotionRenderer(publicDir: string, log: (line: string) => void = console.log): Promise<RenderFn> {
  const started = Date.now();
  await ensureBrowser();
  const serveUrl = await bundle({ entryPoint: path.join(RENDER_ROOT, "src/remotion/index.ts"), publicDir });
  log(`render bundle ready in ${((Date.now() - started) / 1000).toFixed(1)}s`);

  return async (props, outputPath, onProgress) => {
    const inputProps = props as unknown as Record<string, unknown>;
    const composition = await selectComposition({ serveUrl, id: "Highlight", inputProps });
    await renderMedia({
      composition,
      serveUrl,
      codec: "h264",
      audioCodec: "aac",
      outputLocation: outputPath,
      inputProps,
      onProgress: ({ progress }) => onProgress(progress),
    });
  };
}
