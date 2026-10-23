# Contracts

Shared shapes between the iPhone app and the backend. The JSON Schema files here are the source of truth: backend Pydantic models and iOS `Codable` types mirror them, and both sides test against `examples/`. Change them only in a separate PR and tell the team.

| File | What |
|---|---|
| `plan_request.schema.json` | `request` part of `POST /v1/plan` |
| `edit_spec.schema.json` | Response of `POST /v1/plan`; also the fallback planner's output and the renderer's input (TRD §9.1) |
| `style_presets.json` | The four presets (TRD §9.2). The planner prompt and the phone read this file verbatim |
| `style_presets.schema.json` | Shape of `style_presets.json` |
| `error.schema.json` | Body of every non-2xx response |
| `clip_sidecar.schema.json` | `clips/{moment_id}.json`, written by Buffer and read by Edit (phone-internal) |
| `examples/` | One plan request and one edit spec per style (same 12-clip Kyoto trip), an error and a sidecar |
| `check.py` | Validates `style_presets.json` and `examples/` against the schemas |

Check after any change: `pip install jsonschema && python contracts/check.py`.

## Auth

Every request except `GET /healthz` sends `Authorization: Bearer <APP_TOKEN>`. A missing or wrong token gets `401` with `{"code": "unauthorized", "retryable": false}`.

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

### Effective target

`effective_target_s = max(preset.target_s.default, button_count × preset.clip_s.min + preset.end_card_s)`, computed on the phone and sent in the request. Button moments win over the length target (PRD FR-009).

## Style presets

Ranges are `{min, max, default}`. The plan request's `target_s` is `target_s.default`; the fallback planner uses `clip_s.default` and `transition_s.default`. TRD §9.2 leaves some values open; these are first guesses to tune: Documentary dissolve 0.8–1.2 s, Vlog music −18 dB, all `default` values, `title_s`, `end_card_s` 2 s (matches the bundled black clips), and speed ramps allowed for Cinematic and Reels only.
