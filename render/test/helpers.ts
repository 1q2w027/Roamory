import fs from "node:fs";
import path from "node:path";
import type { AgentRequest, AgentResult } from "../src/agent/types";
import type { Style } from "../src/remotion/types";
import { CONTRACTS_DIR } from "../src/server/config";

export const STYLES: Style[] = ["cinematic", "reels", "documentary", "vlog"];

const read = (name: string) => JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, "examples", name), "utf8"));

export const agentRequest = (style: Style): AgentRequest => read(`agent_request_${style}.json`);
export const agentResult = (): AgentResult => read("agent_result_reels.json");
