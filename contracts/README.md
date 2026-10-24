# Contracts

Shared shapes between the iPhone app and Roamory Studio (`studio/`). The JSON Schema files here are the source of truth: the bridge validates against them, iOS `Codable` types mirror them, and both sides test against `examples/`. Change them only in a separate PR and tell the team.

| File | What |
|---|---|
| `studio_request.schema.json` | Body of `POST /v1/studio/jobs` (Mac bridge, `studio/`): trip context and the trip's saved clips |
| `studio_job.schema.json` | Body of `GET /v1/studio/jobs/{job_id}` |
| `studio_result.schema.json` | Body of `GET /v1/studio/jobs/{job_id}/result`: the video's length, title and where each clip lands |
| `style_presets.json` | The four presets (TRD §9). The bridge gives the chosen one to Claude verbatim; the phone reads it for the capture orientation |
| `style_presets.schema.json` | Shape of `style_presets.json` |
| `error.schema.json` | Body of every non-2xx response |
| `evaluate_context.schema.json` | `context` part of `POST /v1/evaluate` (removed, kept for later) |
| `evaluation.schema.json` | Response of `POST /v1/evaluate` (removed, kept for later) |
| `examples/` | A studio request per style (the same 4-clip Kyoto trip), a studio result for Reels, an editing and a failed studio job, a select and a describe evaluate context, and a kept and a skipped evaluation |
| `check.py` | Validates `style_presets.json` and `examples/` against the schemas |

Check after any change: `pip install jsonschema && python contracts/check.py`. It also checks the studio request and result rules below (the studio result against the studio request of the same style).

## `/v1/studio` (Mac bridge)

The Mac bridge (`studio/`, TRD §9) runs on a Mac on the same Wi-Fi as the phone and advertises itself over Bonjour as `_roamory._tcp`, with TXT keys `host` (its `.local` name), `port` and `v` (`1`). Plain HTTP on the local network. Every request except `GET /healthz` and `POST /v1/studio/pair` sends `Authorization: Bearer <token>`; a missing or wrong token gets `401 unauthorized`.

### `POST /v1/studio/pair`

Body `{"code": "123456"}`, the 6-digit code the bridge prints in its terminal. `200` returns `{"token": "...", "name": "<Mac name>"}`. A wrong code gets `401 unauthorized`; after 5 wrong codes the bridge prints a new one.

### `POST /v1/studio/jobs`

Body: a studio request (`application/json`). `201` returns `{"job_id": "..."}` with the job in `uploading`. `429 busy` (retryable) while another job is `uploading` or `editing`.

### `PUT /v1/studio/jobs/{job_id}/clips/{clip_id}.mp4`

Body: the clip file as saved (`video/mp4`, HEVC passthrough), with `Content-Length`. `204`. `404 not_found` for an unknown job or a `clip_id` not in the request; `409 conflict` once the job has started; `413 upload_too_large` over the bridge's `max_clip_mb`.

### `POST /v1/studio/jobs/{job_id}/start`

`202` once every clip is uploaded; `400 bad_request` naming the missing clips otherwise. The job goes to `editing`.

### `GET /v1/studio/jobs/{job_id}`

`200` returns a studio job. Poll until `status` is `completed` or `failed`. A failed job carries an `error` with code `agent_failed`, `agent_timeout` or `internal`.

### `GET /v1/studio/jobs/{job_id}/result`

`200` returns a studio result (`studio_result.schema.json`) once the job is `completed`. Fetch it before the video.

### `GET /v1/studio/jobs/{job_id}/video`

`200` returns the MP4 (H.264 and AAC, `video/mp4`) once the job is `completed`; then the bridge deletes the job. `DELETE /v1/studio/jobs/{job_id}` cancels a job and deletes it.

### Studio request rules

1. `clip_id`s are unique, and each is uploaded exactly once before `/start`.

### Studio effective target

With the style preset `p` and `n` clips totalling `F` seconds: `min(max(p.target_s.default, n × p.clip_s.min + p.title_s + p.end_card_s), F + p.title_s + p.end_card_s)`. Every clip is a button moment, so they all go in; short footage shrinks the target rather than failing.

### Studio result rules

The bridge checks these before completing the job; the phone may rely on them.

1. Every `moments[].clip_id` is a clip of the request, and none repeats.
2. Every clip is in `moments`.
3. `moments` are in playback order and each `0 ≤ start_s < end_s ≤ total_s`.
4. `total_s` is within ±10 % of the effective target and within 0.5 s of the rendered file's duration.

The prompt also tells Claude: clips in chronological order, title text only from the destination, trip type and `start_date`, no invented events, no identifying people. The output size and fps come from the style preset.

## `POST /v1/evaluate` (removed)

Stage 2 moment selection (TRD §8). The service was removed with cloud moment selection; this section and its schemas are kept for when it returns. Requests sent `Authorization: Bearer <APP_TOKEN>`. `Content-Type: multipart/form-data` with:

- one part named `context`: the evaluate context JSON (`application/json`);
- 1 to 3 parts named `frame_0.jpg` … `frame_{n-1}.jpg`, oldest first, the last one at `sample_t_ms` (normally `t−4 s`, `t−2 s`, `t`; fewer only near the start of a recording session). `image/jpeg`, 512 px long edge. No gaps and no other parts.

`200` returns an evaluation. The server applies the S2 weights and thresholds (config), so `keep` is the decision: `false` releases the phone's speculative hold, `true` keeps it.

`purpose = "describe"` is for button moments (TRD §7), sent off the critical path. They are already kept, so the server returns `keep: true`, uses only the fast model, and counts them against a separate cap, not the trip's select budget.

| Status | `code` | `retryable` | When |
|---|---|---|---|
| 400 | `bad_request` | false | `context` missing or invalid, frame parts wrong, or a frame not a JPEG or over the server's `MAX_FRAME_BYTES` |
| 401 | `unauthorized` | false | Bad token |
| 429 | `rate_limited` | false | Over the trip's budget (TRD §8) |
| 502 | `upstream_error` | true | The model API failed or returned unusable output |
| 504 | `upstream_timeout` | true | The model API timed out |
| 500 | `internal` | true | Anything else |

On any error, the phone's 8 s timeout or a network failure, the phone applies the local fallback (TRD §6); button moments are kept regardless.

## Style presets

Ranges are `{min, max, default}`. The studio effective target uses `target_s.default`, `clip_s.min`, `title_s` and `end_card_s`; Claude reads the rest (transition, aspect, output size, whether original audio is kept). These are first guesses to tune. The `music_track` and `music_gain_db` values name tracks the bridge does not have yet (TRD §9).
