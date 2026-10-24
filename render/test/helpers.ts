import fs from "node:fs";
import path from "node:path";
import type { EditSpec, RenderRequest, Style } from "../src/remotion/types";
import type { Slot } from "../src/remotion/timeline";
import { CONTRACTS_DIR } from "../src/server/config";

export const STYLES: Style[] = ["cinematic", "reels", "documentary", "vlog"];

const read = (name: string) => JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, "examples", name), "utf8"));

export const editSpec = (style: Style): EditSpec => read(`edit_spec_${style}.json`);
export const renderRequest = (style: Style): RenderRequest => read(`render_request_${style}.json`);
export const golden = (style: Style): { slots: Slot[]; end_card_start_s: number; total_s: number } =>
  read(`timeline_${style}.json`);
