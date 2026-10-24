import fs from "node:fs";
import path from "node:path";
import { Ajv2020, type ValidateFunction } from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import type { RenderRequest } from "../remotion/types";
import { CONTRACTS_DIR } from "./config";

// ajv-formats is CommonJS; its default export arrives wrapped under ESM.
const addFormats = (addFormatsModule as unknown as { default?: typeof addFormatsModule }).default ?? addFormatsModule;

/** Every contracts/*.schema.json, so their cross-references resolve. Look one up with schemaId(). */
export const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
for (const file of fs.readdirSync(CONTRACTS_DIR).filter((f) => f.endsWith(".schema.json"))) {
  ajv.addSchema(JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, file), "utf8")));
}

export const schemaId = (name: string) => `https://roamory.app/contracts/${name}.schema.json`;
const validateRenderRequest = ajv.getSchema(schemaId("render_request")) as ValidateFunction<RenderRequest>;
/** For tests: the render job shape. */
export const validateRenderJob = ajv.getSchema(schemaId("render_job")) as ValidateFunction;

export type Validation = { ok: true; request: RenderRequest } | { ok: false; message: string };

/**
 * contracts/README.md, "Render request rules": the schema (which includes the edit spec's),
 * then one {moment_id}.mp4 part per clip, trims inside the uploaded files, and edit spec rules 5 and 6 (over_s).
 * @param partNames field names of the uploaded file parts.
 */
export function validateRequest(raw: string | undefined, partNames: string[]): Validation {
  if (raw === undefined) return { ok: false, message: "missing request part" };
  const parsed = parseJson(raw);
  if (!parsed.ok) return { ok: false, message: "request is not JSON" };
  const request = parsed.value;
  if (!validateRenderRequest(request)) {
    return { ok: false, message: `request does not match render_request.schema.json: ${schemaErrors(validateRenderRequest)}` };
  }

  const uploads = new Map(request.clips.map((c) => [c.moment_id, c]));
  const specIds = request.edit_spec.clips.map((c) => c.moment_id);
  if (uploads.size !== request.clips.length || new Set(specIds).size !== specIds.length) {
    return { ok: false, message: "a moment_id repeats" };
  }
  if (specIds.length !== uploads.size || specIds.some((id) => !uploads.has(id))) {
    return { ok: false, message: "clips[] does not match edit_spec.clips" };
  }
  const expected = [...uploads.keys()].map((id) => `${id}.mp4`).sort();
  const parts = [...partNames].sort();
  if (parts.length !== expected.length || parts.some((p, i) => p !== expected[i])) {
    return { ok: false, message: `file parts ${JSON.stringify(parts)} do not match clips ${JSON.stringify(expected)}` };
  }

  for (const clip of request.edit_spec.clips) {
    const upload = uploads.get(clip.moment_id)!;
    if (!(clip.in_s >= 0 && clip.in_s < clip.out_s && clip.out_s <= upload.duration_s + 1e-6)) {
      return { ok: false, message: `${clip.moment_id}: trim [${clip.in_s}, ${clip.out_s}] outside the uploaded ${upload.duration_s} s` };
    }
    if ((clip.transition_in === "cut") !== (clip.transition_s === 0)) {
      return { ok: false, message: `${clip.moment_id}: transition_s must be 0 exactly when transition_in is cut` };
    }
    if (clip.speed_ramp && clip.speed_ramp.over_s > clip.out_s - clip.in_s + 1e-6) {
      return { ok: false, message: `${clip.moment_id}: speed_ramp.over_s is longer than the trim` };
    }
  }
  return { ok: true, request };
}

/** The first few errors of the last validation, on one line. */
export function schemaErrors(validate: ValidateFunction): string {
  return (validate.errors ?? []).slice(0, 5).map((e) => `${e.instancePath || "/"} ${e.message}`).join("; ");
}

export function parseJson(raw: string): { ok: true; value: unknown } | { ok: false } {
  try {
    return { ok: true, value: JSON.parse(raw) };
  } catch {
    return { ok: false };
  }
}
