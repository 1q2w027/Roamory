# Plan: Remotion as a second video renderer

## Context

The highlight video is rendered on the phone today by `ios/RoamoryKit/Sources/RoamoryKit/Edit/Renderer.swift`, which uses AVFoundation and Core Animation `CATextLayer`s (`TitleOverlay.swift`). That covers cuts, fades, dissolves and plain text, but not richer motion graphics such as kinetic titles, animated lower thirds, a map intro, or slide and zoom transitions. Remotion (React → headless Chrome → ffmpeg) can do all of these, but it can't run on an iPhone.

**Decided with the user:** Remotion renders the **whole video in the cloud**, as a new Node service in a top-level `render/` folder. The phone uploads only the trimmed ranges the edit spec uses and downloads the MP4. AVFoundation stays as the default engine and as the fallback whenever the cloud render fails.

The edit spec stays the single input to both engines. The LLM still produces only JSON, and rendering stays deterministic (TRD §1).

This changes a TRD rule ("full video stays on the phone", §1, §2, §11.3). The selected clips now leave the phone when Remotion is chosen, so this needs a decision entry and consent wording before it ships.

## Phase R0: Decision, docs and contracts (PR `contracts/render-request`, tell the team)

- `docs/DECISIONS.md`: add an entry: "Remotion cloud render as an optional engine; trimmed selected clips are uploaded, deleted after download; AVFoundation remains default and fallback."
- `docs/TRD.md` §2, §9.2, §11.3 and §14: add the render service box, the upload exception, the retention rule (clips are deleted when the job ends, the output after download or a `RENDER_TTL_S` of 15 min), and the open question of where it's hosted.
- `CLAUDE.md` layout: add `render/` (Node 22, Remotion; Ian's) and its commands.
- New `contracts/render_request.schema.json`, the `request` part of `POST /v1/render`:
  `{ edit_spec, context: {destination{country,city}, trip_type, start_date}, clips: [{moment_id, duration_s, has_audio}] }`.
  The `edit_spec` here is **rebased**: each clip's `in_s`/`out_s` are relative to the uploaded trimmed file, not the original clip.
- New `contracts/render_job.schema.json`: `{job_id, status: queued|rendering|completed|failed, progress 0..1, error: Error|null}`.
- New `contracts/examples/render_request_*.json`, plus **golden timelines** `examples/timeline_{style}.json` (each slot's start and end, and the total), generated from the iOS `EditTimeline` over the four existing edit spec examples. Both engines test against them so Review's moment times match either render.
- `contracts/README.md`: document the `/v1/render` endpoints and errors (400, 401, 413 `upload_too_large`, 429 `busy`, 500, and job-level `render_failed`). Update `check.py`.
- The edit spec schema is **unchanged** in this phase.

## Phase R1: `render/` Remotion service (PR `render/remotion-service`)

Node 22 + TypeScript, Remotion v4, Express. Bundle once at startup and render with `@remotion/renderer`.

| File | Purpose |
|---|---|
| `render/package.json` | `remotion`, `@remotion/{cli,bundler,renderer,transitions,google-fonts}`, `express`, `multer`, `ajv`, `vitest` (exact versions pinned) |
| `render/src/remotion/Root.tsx` | Registers the `Highlight` composition. `calculateMetadata` sets width, height, fps and `durationInFrames` from the spec |
| `render/src/remotion/timeline.ts` | Port of `Edit/EditTimeline.swift` (`outputLengthS`, `overlapS`, `slots`, `totalDurationS`) |
| `render/src/remotion/Highlight.tsx` | `TransitionSeries` of `<OffthreadVideo>` clips (`fade`/`dissolve` mapped to `@remotion/transitions` fade, overlap = `transition_s`). Title over the start of the first clip, then captions, then the end card after a hard cut. Music via `<Audio>` with gain from `gain_db`, looped or trimmed, and original audio ducked per `duck_original_audio` |
| `render/src/remotion/speedRamp.ts` | Same 4-step ramp as the iOS renderer (constant `playbackRate` per step), so durations match |
| `render/src/remotion/styles/{cinematic,reels,documentary,vlog}.tsx` | Per-style graphics: animated title cards, kinetic captions (Reels), lower thirds (Documentary), end card. This is where the "advanced graphics" live; Andrew's designs go here |
| `render/src/server/index.ts` | `GET /healthz`; `POST /v1/render` (multipart: `request` JSON + one `{moment_id}.mp4` part per clip) returns `202 {job_id}`; `GET /v1/render/:id` returns a job; `GET /v1/render/:id/video` returns the MP4 and then deletes the job dir. Bearer `APP_TOKEN` check. Concurrency 1 (more jobs get 429 `busy`) |
| `render/src/server/jobs.ts` | Job state in memory; job dir under a temp root; serves clips to the renderer on a localhost-only static route; TTL sweep |
| `render/src/server/validate.ts` | Ajv against `contracts/render_request.schema.json` and `edit_spec.schema.json`; checks that the parts match `clips[]` and that the trims fit the uploaded durations |
| `render/scripts/sync-assets.sh` | Copies `contracts/style_presets.json` and `ios/RoamoryKit/Sources/RoamoryKit/Resources/Music/*.m4a` into `render/public/` (like `sync-contracts.sh`) |
| `render/Dockerfile` | `node:22` + Remotion's Chrome deps (`npx remotion browser ensure`) |
| `render/.env` | `APP_TOKEN`, `PORT`, `RENDER_CONCURRENCY`, `RENDER_TTL_S`, `MAX_UPLOAD_MB` (config, not code; add them to `.env.example`) |

**Tests (vitest):** the timeline against the golden `contracts/examples/timeline_*.json`; request validation; auth; 429 when busy; the job lifecycle with a fake renderer. **Smoke script** `render/scripts/smoke.sh`: renders `edit_spec_cinematic.json` against the bundled sample clips with `npx remotion render --props`, then checks the duration with `ffprobe`.

Remotion Studio (`npx remotion studio`) with the example specs as default props doubles as the design playground for Andrew.

## Phase R2: iOS integration (PR series `ios/remote-render-*`)

**R2a. Engine abstraction.**
- In `Edit/Renderer.swift`, add `public protocol VideoRendering: Sendable { func render(_:clipURLs:to:progress:) async throws -> RenderResult }`. The existing `Renderer` conforms with no other change.
- Pull `verify(_:expectedS:)` out as a shared static, so a downloaded MP4 gets the same playable and duration check (TRD §10).
- Add `engine` (`"avfoundation"` or `"remotion"`) to `RenderResult`, and `renderEngine` to `GeneratedVideo`, next to `planSource`.

**R2b. Clip trimmer.** New `Edit/ClipTrimmer.swift`:
- For each spec clip, exports `[in_s, out_s]` with `AVAssetExportSession` (`timeRange`, preset from config, default 1280×720 or 1920×1080).
- Returns the trimmed URLs and the **rebased** spec (`in_s = 0`, `out_s = out_s − in_s`).
- Re-encoding gives frame-exact cuts; passthrough would snap to the 2 s keyframes.

**R2c. Remote renderer.** New `Cloud/RemoteRenderClient.swift`, conforming to `VideoRendering`:
1. Trim the clips.
2. Upload them as multipart, reusing the `PlanClient` multipart helper and the `withTimeout` pattern.
3. Poll the job every `remote_render_poll_s`.
4. Download to `outputURL`, then verify.

Progress is split across upload 0–0.3, render 0.3–0.9 and download 0.9–1. The client is built from Info.plist like `PlanClient.fromBundle` (`RoamoryRenderBaseURL`, same token).

**R2d. Coordinator.** In `Edit/EditCoordinator.swift`, take `renderer: any VideoRendering` plus a `fallbackRenderer: Renderer`:
- Use Remotion only when `config.renderEngine == "remotion"`, a client exists, and `trip.allowCloudAnalysis` is true.
- On any remote error or timeout (`remote_render_timeout_s`, start at 150 s), log it and render locally with AVFoundation. The video always completes.
- `reviewMoments` keeps using the original spec (the golden timelines guarantee the same slot times).

**R2e. Config and lab.**
- `Resources/edit_config.json` and `EditConfig` get `render_engine` (default `"avfoundation"`), `remote_render_timeout_s`, `remote_render_poll_s` and `remote_upload_preset`.
- `RenderLabView` gets an engine picker and shows the elapsed time per engine, so both can be compared side by side on the sample clips.

**Tests (XCTest):**
- the rebase math;
- `RemoteRenderClient` with a `URLProtocol` stub (happy path, a failed job, a timeout);
- the coordinator falling back to AVFoundation when the remote throws;
- `EditTimeline` against the golden timelines.

## Phase R3 (later, optional): Remotion-only graphics in the spec

Once R1 and R2 work end to end, extend the edit spec in its own contracts PR. Candidates are more `transition_in` values (`slide`, `zoom`, `wipe`) and an optional `intro` (for example a destination map), allowed only through a preset flag. `EditSpecValidator` and the backend validator accept them, and the AVFoundation renderer maps unknown transitions to `dissolve` and skips `intro`. The planner prompt learns about them only after this lands.

## Risks and open items

- **Render time:** Remotion at 1080p30 for 60 s is about 1800 frames. On a laptop that's roughly 30–90 s, plus the upload (~30 MB at 720p). Measure in R1 against the 2-minute target. If it misses, render at 720p, raise concurrency, or move to Remotion Lambda.
- **Hosting:** decided: `render/` runs with the backend in one Fly.io app (TRD §2, `cloud/`), with a laptop on the venue network as the fallback.
- **Remotion license:** it's free for individuals and companies of up to 3 people. Check whether our 4-person team needs a company license.
- **Consent:** the cloud consent screen (Daniel's) must say that selected clips are uploaded for rendering and then deleted.

## Verification

- Contracts: `python contracts/check.py` passes with the new schemas and examples.
- Render service: `cd render && npm test`, then `scripts/smoke.sh` for each style. Each MP4 has the right size and fps, and its duration matches the golden total within 0.5 s.
- Manual API check: `curl -H "Authorization: Bearer $APP_TOKEN" -F request=@../contracts/examples/render_request_reels.json -F m_01.mp4=@… localhost:3000/v1/render`, then poll and download.
- iOS: `cd ios/RoamoryKit && swift test`.
- On device, RenderLab with each engine × each preset × 1, 3 and 10 clips (TRD §12.2 render matrix):
  - each output plays in the app and in Photos;
  - the Review moment times line up;
  - the time per render is logged.
- Fault paths:
  - render service down, a failed job, consent off, or a forced timeout: each still produces a video through AVFoundation, with `renderEngine = "avfoundation"` in `generated_video.json`;
  - the server deletes the job dir after download and after the TTL.
