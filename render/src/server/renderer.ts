import net, { type AddressInfo } from "node:net";
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
    const port = await freePort();
    const composition = await selectComposition({ serveUrl, id: "Highlight", inputProps, port });
    await renderMedia({
      composition,
      serveUrl,
      port,
      codec: "h264",
      audioCodec: "aac",
      outputLocation: outputPath,
      inputProps,
      onProgress: ({ progress }) => onProgress(progress),
    });
  };
}

/**
 * A free loopback port for Remotion's bundle server. Left to its own search on macOS it can bind
 * 127.0.0.1 on our API's port (beside our wildcard listen), and Chrome then loads our API instead.
 */
function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = net.createServer().once("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const { port } = probe.address() as AddressInfo;
      probe.close(() => resolve(port));
    });
  });
}
