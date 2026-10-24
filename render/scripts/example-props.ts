// Prints Highlight props for one contract example over the sample clips (scripts/smoke.sh).
// Usage: tsx scripts/example-props.ts <style>
import fs from "node:fs";
import path from "node:path";
import { exampleProps } from "../src/remotion/examples";
import type { Style } from "../src/remotion/types";
import { RENDER_ROOT } from "../src/server/config";

const style = process.argv[2] as Style;
const props = exampleProps(style);
const pub = path.join(RENDER_ROOT, "public");
for (const { src } of Object.values(props.clips)) {
  if (!fs.existsSync(path.join(pub, src))) throw new Error(`public/${src} is missing: run scripts/sync-assets.sh`);
}
if (props.music_src && !fs.existsSync(path.join(pub, props.music_src))) {
  console.error(`warning: public/${props.music_src} is missing; rendering without music`);
  props.music_src = null;
}
process.stdout.write(JSON.stringify(props));
