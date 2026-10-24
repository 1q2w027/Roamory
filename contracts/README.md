# Contracts

Shared shapes between the iPhone app, the backend and the render service (`render/`). The JSON Schema files here are the source of truth: backend Pydantic models, iOS `Codable` types and the render service mirror them, and test against `examples/`. Change them only in a separate PR and tell the team.

| File | What |
|---|---|
| `style_presets.json` | The four presets (TRD §9.2). The agent and the phone read this file verbatim |
| `style_presets.schema.json` | Shape of `style_presets.json` |
| `error.schema.json` | Body of every non-2xx response |
| `clip_sidecar.schema.json` | `clips/{moment_id}.json`, written by Buffer and read by Edit (phone-internal) |
| `agent_request.schema.json` | `request` part of `POST /v1/agent` (render service): trip context and every candidate clip |
| `agent_result.schema.json` | Body of `GET /v1/agent/{job_id}/result`: the video's length, title and where each moment lands |
| `render_job.schema.json` | Body of `GET /v1/agent/{job_id}` |
| `evaluate_context.schema.json` | `context` part of `POST /v1/evaluate` |
| `evaluation.schema.json` | Response of `POST /v1/evaluate` (TRD §8.2) |
| `examples/` | An agent request per style (same 12-clip Kyoto trip) and an agent result for Reels. Also render jobs, a sidecar, a select and a describe evaluate context, and a kept and a skipped evaluation |
| `check.py` | Validates `style_presets.json` and `examples/` against the schemas |

Check after any change: `pip install jsonschema && python contracts/check.py`. It also checks the agent request and result rules below (an agent result against the agent request of the same style).

## Auth

Same for the backend and the render service: every request except `GET /healthz` sends `Authorization: Bearer <APP_TOKEN>`. A missing or wrong token gets `401` with `{"code": "unauthorized", "retryable": false}`.

## `POST /v1/evaluate`

Stage 2 moment selection (TRD §8.2). `Content-Type: multipart/form-data` with:

- one part named `context`: the evaluate context JSON (`application/json`);
- 1 to 3 parts named `frame_0.jpg` … `frame_{n-1}.jpg`, oldest first, the last one at `sample_t_ms` (normally `t−4 s`, `t−2 s`, `t`; fewer only near the start of a recording session). `image/jpeg`, 512 px long edge. No gaps and no other parts.

`200` returns an evaluation. The model decides keep or skip itself (no scores), so `keep` is the decision: `false` releases the phone's speculative hold, `true` keeps it.

`purpose = "describe"` is for button moments (TRD §7), sent off the critical path. They are already kept, so the server returns `keep: true`, uses only the fast model, and counts them against a separate cap, not the trip's select budget.

| Status | `code` | `retryable` | When |
|---|---|---|---|
| 400 | `bad_request` | false | `context` missing or invalid, frame parts wrong, or a frame not a JPEG or over the server's `MAX_FRAME_BYTES` |
| 401 | `unauthorized` | false | Bad token |
| 429 | `rate_limited` | false | Over the trip's budget (TRD §8.3) |
| 502 | `upstream_error` | true | The model API failed or returned unusable output |
| 504 | `upstream_timeout` | true | The model API timed out |
| 500 | `internal` | true | Anything else |

On any error, the phone's 8 s timeout or a network failure, the phone applies the local fallback (TRD §6); button moments are kept regardless.

## Render service: `/v1/agent`

The only way the app makes the video (TRD §9): a Claude agent in the render service picks, trims and edits the clips, writes its own Remotion composition, renders and checks it. The phone never retries an agent job on its own; on any error, timeout or failed job, Processing shows the error and the traveller can Retry.

### `POST /v1/agent`

`Content-Type: multipart/form-data` with:

- one part named `request`: the agent request JSON (`application/json`);
- one part per clip named `{moment_id}.mp4` (`video/mp4`): the **whole** candidate clip, re-encoded on the phone at the upload preset (720p). Not trimmed: the agent chooses the trims.

`202` returns `{"job_id": "..."}`.

### `GET /v1/agent/{job_id}`

`200` returns a render job (`render_job.schema.json`). Poll it until `status` is `completed` or `failed`. A failed job carries an `error` with code `agent_failed`, `agent_timeout` or `internal`.

### `GET /v1/agent/{job_id}/result`

`200` returns an agent result once the job is `completed`. `404 not_found` before then or after the job is deleted. Fetch it before the video, since downloading the video deletes the job.

### `GET /v1/agent/{job_id}/video`

`200` returns the MP4 (`video/mp4`) once the job is `completed`, then the server deletes the job. The phone checks the file plays and its duration matches the result's `total_s` (TRD §10).

### Retention

The uploaded clips and the agent's workspace are deleted when the job ends (completed or failed). The output is deleted after it is downloaded, or `RENDER_TTL_S` (15 min) after the job ends, whichever comes first. Logs hold ids, timings, turn and render counts, cost and error codes, never video or frames.

### Errors

| Status | `code` | `retryable` | When |
|---|---|---|---|
| 400 | `bad_request` | false | Request JSON missing or invalid, the clip parts don't match `clips[]`, or a proposed window falls outside its uploaded file |
| 401 | `unauthorized` | false | Bad token |
| 404 | `not_found` | false | Unknown or already-deleted `job_id`, or result or video requested before the job completed |
| 413 | `upload_too_large` | false | The upload is over the server's `MAX_UPLOAD_MB` |
| 429 | `busy` | true | The server is already running `RENDER_CONCURRENCY` jobs |
| 429 | `rate_limited` | false | The trip is over the server's `AGENTS_PER_TRIP` |
| 500 | `internal` | true | Anything else |

Job-level codes, reported in the job's `error`, not as an HTTP status:

| `code` | `retryable` | When |
|---|---|---|
| `agent_failed` | false | The agent ended without a valid result (no render, or `submit` never passed the rules below), or its render failed |
| `agent_timeout` | false | The job ran past the server's `AGENT_TIMEOUT_S` |

### Agent request rules

1. `moment_id`s are unique, and there is exactly one `{moment_id}.mp4` part for each.
2. `0 ≤ proposed_in_s < proposed_out_s ≤ duration_s` of the uploaded file.

`effective_target_s`: see Effective target.

### Agent result rules

The server checks these before completing the job (the agent's `submit`); the phone may rely on them.

1. Every `moments[].moment_id` is in the request, and none repeats.
2. Every `source = button` clip is in `moments`.
3. `moments` are in playback order and each `0 ≤ start_s < end_s ≤ total_s`.
4. `total_s` is within ±10 % of `effective_target_s` and within 0.5 s of the rendered file's duration.

Not enforced, but the agent is told: clips in chronological order, title text only from the destination, trip type and `start_date`, captions only from those or a clip's `description`, no invented events, no identifying people. The output size and fps come from the style preset, not the agent.

## Effective target

`effective_target_s = max(preset.target_s.default, button_count × preset.clip_s.min + preset.end_card_s)`, computed on the phone and sent in the agent request. Button moments win over the length target (PRD FR-009).

## Style presets

Ranges are `{min, max, default}`. The agent request's `target_s` is `target_s.default`; the phone's pre-pass proposes windows of `clip_s.default`. The agent gets its style's preset and is told to follow it; the output size and fps come from it. TRD §9.2 leaves some values open; these are first guesses to tune: Documentary dissolve 0.8–1.2 s, Vlog music −18 dB, all `default` values, `title_s`, `end_card_s` 2 s, and speed ramps allowed for Cinematic and Reels only.
