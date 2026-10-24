# Contracts

Shared shapes between the iPhone app, the backend and the render service (`render/`). The JSON Schema files here are the source of truth: backend Pydantic models and iOS `Codable` types mirror them, and both sides test against `examples/`. Change them only in a separate PR and tell the team.

| File | What |
|---|---|
| `plan_request.schema.json` | `request` part of `POST /v1/plan` |
| `edit_spec.schema.json` | Response of `POST /v1/plan`; also the fallback planner's output and the renderer's input (TRD §9.1) |
| `style_presets.json` | The four presets (TRD §9.2). The planner prompt and the phone read this file verbatim |
| `style_presets.schema.json` | Shape of `style_presets.json` |
| `error.schema.json` | Body of every non-2xx response |
| `clip_sidecar.schema.json` | `clips/{moment_id}.json`, written by Buffer and read by Edit (phone-internal) |
| `render_request.schema.json` | `request` part of `POST /v1/render` (render service): a rebased edit spec, trip context and the uploaded clips |
| `render_job.schema.json` | Body of `GET /v1/render/{job_id}` |
| `timeline.schema.json` | Golden timelines: where each clip of an example edit spec lands in the video |
| `examples/` | Per style (same 12-clip Kyoto trip): a plan request, an edit spec, a render request and a golden timeline. Also errors, render jobs and a sidecar |
| `check.py` | Validates `style_presets.json` and `examples/` against the schemas |

Check after any change: `pip install jsonschema && python contracts/check.py`. It also checks that each render request's clips match its edit spec and that each golden timeline lines up with its edit spec.

## Auth

Same for the backend and the render service: every request except `GET /healthz` sends `Authorization: Bearer <APP_TOKEN>`. A missing or wrong token gets `401` with `{"code": "unauthorized", "retryable": false}`.

## `POST /v1/plan`

`Content-Type: multipart/form-data` with:

- one part named `request`: the plan request JSON (`application/json`);
- for each clip, `thumbnail_count` parts named `{moment_id}_{k}.jpg`, k = 0..`thumbnail_count`−1 (`image/jpeg`, 384 px long edge, quality about 0.7, evenly spaced through the proposed window).

`200` returns an edit spec. Errors return the error shape:

| Status | `code` | `retryable` | When |
|---|---|---|---|
| 400 | `bad_request` | false | Request JSON missing or invalid, or thumbnail parts don't match `thumbnail_count` |
| 401 | `unauthorized` | false | Bad token |
| 413 | `too_many_clips` | false | More clips than the server's `MAX_PLAN_CLIPS` |
| 422 | `invalid_plan` | false | The model's spec failed validation twice |
| 429 | `rate_limited` | false | Over `PLANS_PER_TRIP` for this `trip_id` |
| 502 | `upstream_error` | true | The model API failed |
| 504 | `upstream_timeout` | true | The model API timed out |
| 500 | `internal` | true | Anything else |

On any error, timeout or network failure the phone uses its fallback planner; it never blocks on a retry.

## Edit spec rules

The schema checks shape. Both the backend validator and the phone's `EditSpecValidator` also check these, so a spec is valid only if all hold. `examples/` passes all of them.

1. Every `clips[].moment_id` exists in the request, and none repeats.
2. `0 ≤ in_s < out_s ≤ duration_s` for that clip.
3. Clip length `out_s − in_s` (source seconds) is within the preset's `clip_s` min/max.
4. Every `source = button` clip is included.
5. `transition_s = 0` exactly when `transition_in = cut`.
6. `speed_ramp` is null unless the preset has `allow_speed_ramp`; when set, `in_s + over_s ≤ low_fps_lead_in_s` and `over_s ≤ out_s − in_s`.
7. `caption` is null unless the preset has `captions`; when set, it equals exactly one of: the destination city, the country, `"{city}, {country}"`, the trip type, or a clip's `description` (PRD FR-015).
8. Total duration is within ±10 % of `effective_target_s`.

Not enforced, but expected: clips in chronological order (`t_from_ms`), near-duplicates dropped, `output` and `music` copied from the preset with `duck_original_audio = !keep_original_audio`, and title text drawn only from the destination, trip type and `start_date`.

### Duration

- Clip output length is `out_s − in_s`, except a speed-ramped clip, where the first `over_s` source seconds are split into 4 equal steps played at rates `r_k = from + (to − from)·k/3`, k = 0..3, giving `Σ (over_s/4) / r_k` output seconds. Rates are multipliers: 4.0 is 4× fast (time-lapse), 1.0 is real time.
- Total = Σ clip output lengths − Σ `transition_s` of every clip after the first whose transition is not `cut` (the overlap) + `end_card.duration_s`.
- The title is overlaid on the first clip and adds nothing. On the first clip, `fade`/`dissolve` means from black and overlaps nothing.

### Golden timelines

`examples/timeline_{style}.json` holds each slot's `start_s`/`end_s`, `end_card_start_s` and `total_s` (output seconds, rounded to 1 ms) for `examples/edit_spec_{style}.json`. They were generated from the iOS `EditTimeline`. The iOS renderer and the render service both test against them, within 1 ms, so Review's moment times are right whichever engine rendered the video. Regenerate them when the duration rules or the edit spec examples change.

### Effective target

`effective_target_s = max(preset.target_s.default, button_count × preset.clip_s.min + preset.end_card_s)`, computed on the phone and sent in the request. Button moments win over the length target (PRD FR-009).

## Render service: `/v1/render`

Optional cloud engine (TRD §9.2): Remotion renders the whole video. The on-phone AVFoundation renderer stays the default and is the fallback on **any** error, timeout or failed job; the phone never retries a render. Used only when `render_engine` is `remotion` and "Allow cloud analysis" is on.

### `POST /v1/render`

`Content-Type: multipart/form-data` with:

- one part named `request`: the render request JSON (`application/json`);
- one part per clip named `{moment_id}.mp4` (`video/mp4`): the clip trimmed on the phone to the edit spec's `[in_s, out_s]`, re-encoded so the cut is frame-exact.

`202` returns `{"job_id": "..."}`.

### `GET /v1/render/{job_id}`

`200` returns a render job. Poll it until `status` is `completed` or `failed`. A failed job carries an `error` with code `render_failed` (or `internal`); the phone then renders locally.

### `GET /v1/render/{job_id}/video`

`200` returns the MP4 (`video/mp4`) once the job is `completed`, then the server deletes the job. `404 not_found` before then or after deletion. The phone checks the file plays and its duration matches `total_s` (TRD §10) before treating it as done.

### Retention

The uploaded clips are deleted when the job ends (completed or failed). The output is deleted after it is downloaded, or `RENDER_TTL_S` (15 min) after the job ends, whichever comes first. Nothing is logged except ids, timings and error codes.

### Errors

| Status | `code` | `retryable` | When |
|---|---|---|---|
| 400 | `bad_request` | false | Request JSON missing or invalid, the clip parts don't match `clips[]`, or a trim falls outside its uploaded file |
| 401 | `unauthorized` | false | Bad token |
| 404 | `not_found` | false | Unknown or already-deleted `job_id`, or video requested before the job completed |
| 413 | `upload_too_large` | false | The upload is over the server's `MAX_UPLOAD_MB` |
| 429 | `busy` | true | The server is already rendering `RENDER_CONCURRENCY` jobs |
| 500 | `internal` | true | Anything else |
| (job) | `render_failed` | false | The render itself failed; reported in the job's `error`, not as an HTTP status |

### Render request rules

The edit spec in a render request is **rebased**: each clip's `in_s`/`out_s` are seconds from the start of its uploaded trimmed file (normally `in_s = 0`, `out_s` = the original `out_s − in_s`). Everything else in the spec is unchanged, so the timeline, and the golden timelines, are the same as for the original spec. The render service checks:

1. `clips[]` and `edit_spec.clips` have the same `moment_id`s, none repeats, and there is exactly one `{moment_id}.mp4` part for each.
2. `0 ≤ in_s < out_s ≤ duration_s` of the uploaded file.
3. The edit spec rules that don't need the plan request: 5 (`transition_s` vs `cut`) and, for a `speed_ramp`, `over_s ≤ out_s − in_s`.

The phone already validated the original spec against the plan request, so rules 1, 3, 4, 6 (lead-in), 7 and 8 are not rechecked.

## Style presets

Ranges are `{min, max, default}`. The plan request's `target_s` is `target_s.default`; the fallback planner uses `clip_s.default` and `transition_s.default`. TRD §9.2 leaves some values open; these are first guesses to tune: Documentary dissolve 0.8–1.2 s, Vlog music −18 dB, all `default` values, `title_s`, `end_card_s` 2 s (matches the bundled black clips), and speed ramps allowed for Cinematic and Reels only.
