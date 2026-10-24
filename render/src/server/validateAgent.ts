import fs from "node:fs";
import path from "node:path";
import type { ValidateFunction } from "ajv/dist/2020.js";
import type { AgentRequest, StylePreset } from "../agent/types";
import type { Style } from "../remotion/types";
import { CONTRACTS_DIR } from "./config";
import { ajv, parseJson, schemaErrors, schemaId } from "./validate";

/** contracts/style_presets.json: the agent gets its style's preset, and the output size and fps come from it. */
export const presets: Record<Style, StylePreset> = JSON.parse(
  fs.readFileSync(path.join(CONTRACTS_DIR, "style_presets.json"), "utf8"),
).presets;

const validateAgentRequest = ajv.getSchema(schemaId("agent_request")) as ValidateFunction<AgentRequest>;

export type AgentValidation = { ok: true; request: AgentRequest } | { ok: false; message: string };

/**
 * contracts/README.md, "Agent request rules": the schema, unique moment_ids with one {moment_id}.mp4
 * part each, and proposed trims inside the uploaded files.
 * @param partNames field names of the uploaded file parts.
 */
export function validateAgentRequestParts(raw: string | undefined, partNames: string[]): AgentValidation {
  if (raw === undefined) return { ok: false, message: "missing request part" };
  const parsed = parseJson(raw);
  if (!parsed.ok) return { ok: false, message: "request is not JSON" };
  const request = parsed.value;
  if (!validateAgentRequest(request)) {
    return { ok: false, message: `request does not match agent_request.schema.json: ${schemaErrors(validateAgentRequest)}` };
  }

  const ids = request.clips.map((c) => c.moment_id);
  if (new Set(ids).size !== ids.length) return { ok: false, message: "a moment_id repeats" };
  const expected = ids.map((id) => `${id}.mp4`).sort();
  const parts = [...partNames].sort();
  if (parts.length !== expected.length || parts.some((p, i) => p !== expected[i])) {
    return { ok: false, message: `file parts ${JSON.stringify(parts)} do not match clips ${JSON.stringify(expected)}` };
  }
  for (const clip of request.clips) {
    if (!(clip.proposed_in_s >= 0 && clip.proposed_in_s < clip.proposed_out_s && clip.proposed_out_s <= clip.duration_s + 1e-6)) {
      return {
        ok: false,
        message: `${clip.moment_id}: proposed [${clip.proposed_in_s}, ${clip.proposed_out_s}] outside the uploaded ${clip.duration_s} s`,
      };
    }
  }
  return { ok: true, request };
}
