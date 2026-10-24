import type { Style } from "../types";
import { cinematic } from "./cinematic";
import type { StyleGraphics } from "./common";
import { documentary } from "./documentary";
import { reels } from "./reels";
import { vlog } from "./vlog";

export const graphics: Record<Style, StyleGraphics> = { cinematic, reels, documentary, vlog };
