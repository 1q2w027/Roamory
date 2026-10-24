# Roamory — Technical Requirements Document

Oct 23, 2026 · v2.1 (iPhone pivot; iOS 26 target). Replaces v1.0 (glasses + Raspberry Pi), which is discarded.

> **How to read this document.** It implements `docs/PRD.md` v2.0. Choices that come from the PRD's **(Decided)** items are stated plainly. Everything else is a **proposal** by the author, to be confirmed or changed; Section 14 lists what is open. iOS API names are from the author's knowledge and must be checked against current Apple documentation during the first spike.

## 1. Overview

Roamory is an iPhone app that films a trip with the screen dark, keeps the moments that matter in a rolling buffer, and builds a highlight video the user reviews in the app. Cloud AI (a frontier vision model) selects the moments.

**In scope:** interactive onboarding, camera capture at a fixed 30 fps, in-memory ring buffer and moment saving, Bluetooth button, cloud moment selection, video editing and rendering by a Claude agent in the cloud, in-app review.

**Deferred:** adaptive frame rate (§4.3, PRD FR-008); per-window holds and partial clips (§5.3).

**Out of scope (PRD §3.3):** extra hardware, Android, background camera capture, manual timeline editing, multi-user features.

**Design constraints that drive most decisions**

- Recording never waits on the network or AI. The phone holds footage in memory and saves it locally; the cloud only says "keep" or "skip". Footage that is not selected is never written to disk.
- During the trip only small sample frames go to the cloud. When the trip ends, every kept clip is uploaded at 720p to the render service, which makes the video and deletes them after (§9, §11.3).
- The camera cannot run in the background on iOS, so the app stays in the foreground, with the screen at brightness 0 and auto-lock disabled, for the whole trip.
- Frontier model calls are slow (1–5 s) and metered, so cheap on-phone checks decide when to ask.
- The video is made by a Claude agent in the render service: it watches the clips, writes and renders its own Remotion composition, and the server checks the result against fixed rules (§9.2). There is no on-phone renderer or fallback; a failed job shows an error with Retry.

| Term | Meaning |
|---|---|
| Session | One continuous recording run; a trip has one or more (PRD FR-007b) |
| Ring buffer | An in-memory queue of the last `BUFFER_RETENTION_S` of encoded video samples (and audio, if enabled); nothing in it is on disk until a moment is saved (§5) |
| Hold | References to the buffered samples around a moment, kept so they outlive the ring buffer's trimming (§5.3) |
| Trip clock | Wall-clock milliseconds since trip start, `t_ms`; it keeps running while paused, so sessions leave gaps |
| Stage 1 | The on-phone signals and escalation gate (§6) |
| Stage 2 | The cloud evaluation (§8.2): one call to a fast vision model |
| Tier | A camera frame-rate level (for example 30, 15, 10 fps); deferred with §4.3 |
| Sample | A downscaled JPEG frame used for on-phone checks and cloud evaluation |
| Candidate | A sample that passed the on-phone gate and is sent to the cloud |
| Moment | A kept window `[T−pre, T+post]` around a trigger time T |
| Clip | The finalized video file for one moment |
| Agent result | What the video agent reports with the MP4: its length, title, and where each moment lands (§9.2) |

## 2. System architecture

Three components: the **iOS app**, which does everything except the model calls and the video; a thin **cloud backend** that holds the model API key and evaluates moments; and the **render service** (`render/`), where a Claude agent makes the highlight video with Remotion (§9).

```text
 iPhone app                                   Cloud backend (FastAPI)
 ┌──────────────────────────────┐            ┌─────────────────────┐
 │ Onboarding UI (SwiftUI)      │  frames    │ POST /v1/evaluate   │
 │ Capture (fixed 30 fps)       │ ────────►  │   → Stage 2 model   │
 │ Ring buffer + clip writer    │  keep/skip │ GET  /healthz       │
 │ On-phone gate (signals)      │ ◄────────  └─────────────────────┘
 │ Bluetooth button             │                    │
 │ Review UI                    │                    ▼
 └──────────────────────────────┘           Frontier vision model API
        │  kept clips ▲ MP4 + result                 ▲
        ▼  (720p)     │                              │
 ┌──────────────────────────────┐                    │
 │ Render service (Agent SDK,   │ ───────────────────┘
 │ Remotion) POST /v1/agent     │
 └──────────────────────────────┘
```

- **Proposal:** the backend stores no trip data in the MVP; all trip data lives on the phone. Its only state is in-memory call counters per trip for the budget caps (§8.3), which reset if the process restarts. That is acceptable for the demo.
- **Decided:** the video is made in the cloud by the agent (§9), which settles PRD open question 3. The kept clips are uploaded and deleted when the job ends (§11.3). The on-phone AVFoundation renderer, the fixed Remotion composition and the `/v1/plan` planner were removed (`docs/DECISIONS.md`).
- **Decided:** the backend and the render service run together in one Fly.io app (`cloud/`, settings in `cloud/fly.toml`) on one machine (the budget counters and agent jobs are in memory) that never auto-stops, so jobs continue between polls. A Caddy proxy routes `/v1/agent*` to the render service and the rest to the backend. Google Cloud was dropped. Redeploying restarts both, which resets the budgets and drops in-flight jobs. Laptop hosting (`scripts/dev.sh`) still works for development.
- Backend repo folder: `backend/`. App folder: `ios/`.

## 3. iOS app

**Target: iOS 26 (Decided).** Deployment target iOS 26.0, built with Xcode 26; test devices must be iPhone 11 or later (the oldest hardware iOS 26 supports). Every API named in this document, including `AVCaptureEventInteraction` (§7) and SwiftData (§3.3), is available at that target, so no availability checks or fallbacks are needed.

**Proposal:** native Swift and SwiftUI, distributed by TestFlight or a development build for the hackathon. (PRD open question 8.)

### 3.1 Modules

| Module | Responsibility |
|---|---|
| `Onboarding/` | Style picker, destination globe, trip-type deck, trip length, permissions and consent, mounting guide, Start button |
| `Preferences/` | Persist personal preference data |
| `Capture/` | Camera session, HEVC encoder |
| `RingBuffer/` | Ring buffer, holds, clip writer |
| `Signals/` | On-phone sample signals and the escalation gate |
| `Cloud/` | Client for the backend, budget, timeouts, fallback |
| `Button/` | Bluetooth button input and confirmation haptic |
| `Edit/` | Pre-pass, agent request, upload and download, video checks |
| `Review/` | Playback, moment list, feedback |
| `Config/` | Thresholds, model-independent settings (loaded from a bundled file, not hard-coded) |

### 3.2 Onboarding implementation (PRD §4)

- **Style picker (FR-001):** four bundled sample clips in `AVPlayer`s using `AVPlayerLooper`, muted. Tap expands the chosen clip with sound using a matched-geometry transition. Sample clips are bundled assets (PRD open question 9).
- **Destination (FR-002):** an interactive 3D globe (SceneKit or RealityKit) with country polygons from a bundled Natural Earth GeoJSON for tap hit-testing, and a bundled city list for pins. Zoom, glow and pulse animations as in the mockup. MapKit is the fallback if the globe takes too long.
- **Trip type (FR-003):** a SwiftUI gesture-driven card deck (the PRD's leading idea). The set of types is a config list.
- **Trip length (FR-004):** a day-count picker.
- **Permissions and consent (FR-005a):** request each permission just before the step that needs it, not all at launch. The cloud consent screen sets `allowCloudAnalysis`.
- **Mounting guide (FR-007a):** an illustration of the regular chest mount (PRD FR-007a) in the orientation the style needs.
- **Output:** a `TripSetup` value `{style, destination{continent,country,city}, tripType, lengthDays, allowCloudAnalysis}`. Capture orientation is derived from `style`.

### 3.3 Persistence

**Proposal:** SwiftData. Tables below. Preference data is local only; no account.

| Entity | Fields |
|---|---|
| `UserPreferences` | `style`, `tripTypeHistory[]`, `destinationHistory[]`, `allowCloudAnalysis` |
| `Trip` | `id`, `style`, `destination`, `tripType`, `lengthDays`, `status`, `startedAt`, `endedAt` |
| `RecordingSession` | `id`, `tripId`, `startedMs`, `endedMs`, `endReason` (user / interruption / background / low_battery / thermal) |
| `Moment` | `id`, `tripId`, `sessionId`, `triggerMs`, `fromMs`, `toMs`, `status` (held / kept / released / finalized), `source` (ai / button / local_fallback), `eventType`, `description`, `score`, `clipPath`, `bestFrameDhash` |
| `Evaluation` | `id`, `momentId`, `latencyMs`, `response` (JSON), `error` |
| `GeneratedVideo` | `id`, `tripId`, `status`, `editSpec` (JSON), `outputPath`, `durationS`, `style`, `createdAt`, `error` |

The ring buffer is not persisted, so there is no index to recover. A saved clip has a sidecar JSON written after the clip finishes; a clip without one is partial (§5.4).

## 4. Capture and the dark screen

### 4.1 Camera session (FR-007)

- `AVCaptureSession` with the back wide camera; **proposal:** 1080p HEVC, 30 fps maximum. Landscape (1920×1080) for 16:9 styles, portrait (1080×1920) for Reels, matching how the phone is worn (PRD FR-007a), so the edit never crops to a different aspect.
- An orientation check from `CMMotionManager` gravity runs at Start Recording and every few seconds after; a wrong orientation gives a haptic and a spoken prompt.
- Video frames come from `AVCaptureVideoDataOutput`. They go to a `VTCompressionSession` (HEVC, hardware, real-time, no frame reordering, keyframe every 2 s by duration) whose encoded output fills the ring buffer (§5), and to a low-rate sampler for signals (§6).
- Audio is off by default. If enabled by the user, `AVCaptureAudioDataOutput` samples are held in the ring buffer and encoded to AAC when a clip is written.
- **Fixed frame rate:** 30 fps for the whole session. Adaptive frame rate is deferred (§4.3).
- **Safety guards:** `ProcessInfo.thermalState` of `.serious` shows a warning on the status view; `.critical` pauses the trip (§4.4). Battery under 10% pauses the trip with a notice, so the user can charge and resume.

### 4.2 Dark screen

- On session start: store the window scene screen's `brightness` (`UIScreen.main` is deprecated), set it to 0, set `UIApplication.shared.isIdleTimerDisabled = true`.
- The recording UI is pure black (black OLED pixels draw almost no power) with a minimal status layer. Tap-and-hold wakes the status view and the End Trip control.
- On pause, on trip end, on leaving the app, and on a crash restart, restore the stored brightness. Always restore it.
- A visible recording indicator is required whenever the status view is shown (PRD §10).

### 4.3 Adaptive frame rate (FR-008) — Deferred

> **Deferred.** For now the app records at a fixed 30 fps (§4.1) and none of this section is built. The design is kept for when battery data says it is needed. Everything else in this document works without it. The thermal and battery guards that were part of this section now live in §4.1.

Frame rate is changed at run time by locking the device and setting `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration` to `1/fps`, clamped to the active format's `videoSupportedFrameRateRanges`. **The first spike must confirm that changing these mid-session does not drop or stall the encoder or the clip writer.**

**Tier controller** (a small state machine, config-driven):

| Setting | Proposed default |
|---|---|
| Tiers | `[30, 15, 10]` fps; floor set by the battery spike |
| Ramp-up | Immediately to 30 fps on any trigger |
| Ramp-down | One tier per `TIER_HOLD_S` (25 s) with no trigger |
| Floor | Lowest tier; never below the spike-approved value |

**Ramp-up triggers** (all local, no network):

| Trigger | Source |
|---|---|
| User slows or stops (dwell) | `CMMotionActivityManager` / `CMMotionManager` |
| Phone raised or tilted | `CMMotionManager` attitude change |
| Scene change spike | A cheap frame difference on a 64×36 grayscale copy every 0.5 s, separate from the 2 s sampler in §6, so ramp-up meets the PRD's "within about a second" |
| Bluetooth button | §7 |
| Near a landmark (optional) | `CLLocationManager` vs. bundled landmark list for the chosen city |
| Loud sound (optional) | Microphone level, only if the user allowed audio |

**Safety caps (when tiers return):** `ProcessInfo.thermalState` of `.serious` caps the tier at the floor. The `.critical` and low-battery pauses already apply (§4.1, §4.4).

Timestamps stay in real time, so low-fps footage plays at normal speed with fewer frames. The edit stage can turn low-fps lead-ins into a speed-ramp (§9).

### 4.4 Pauses and interruptions (PRD FR-007b)

The trip **pauses** (state `PAUSED`, §10) on the Pause control, `AVCaptureSession` interruption notifications (calls, other apps), backgrounding, low battery, or thermal `.critical`. Pausing:

1. Stops capture, flushes the encoder, and ends the `RecordingSession` with its `endReason`.
2. Finalizes every pending moment with the footage held so far (§5.3). Moments never span sessions.
3. Clears the ring buffer, so a paused trip holds only clips.
4. Restores brightness and posts a local notification that recording stopped.

Resuming takes a user action and starts a new `RecordingSession` on the same trip clock. Only End Trip moves the trip to `FINALIZING`. When `lengthDays` has passed, the app reminds the user to end the trip; it does not end it on its own.

## 5. Ring buffer (FR-008a)

The buffer is a queue in memory. Nothing is written to disk until a moment is saved.

### 5.1 What is buffered

**Proposal:** encoded samples, not raw frames. Each encoded video `CMSampleBuffer` from the compression session (§4.1) is appended with its presentation time, a keyframe flag and its trip-clock time `t_ms`. Audio, when enabled, is held as PCM samples (under 10 MB for 45 s) and encoded when a clip is written.

Raw frames are never held: a 1080p frame is about 3 MB, so 45 s at 30 fps is several GB, and camera buffers that are not returned promptly stall capture.

The buffer has four operations: append, trim before a time, read a time range, and find the keyframe at or before a time. They depend only on timestamps and keyframe flags, so the buffer is a plain Swift type that XCTest can drive with fake samples, without AVFoundation.

### 5.2 Retention (runs on every append)

Drop samples older than `BUFFER_RETENTION_S`.

**Proposal:** `BUFFER_RETENTION_S = 45`, about 50 MB at 8-10 Mbps. This covers the 15 s pre-roll, the Stage 1 delay (about 4 s, §11.1) and up to 2 s back to the previous keyframe, with generous headroom. It can be small because a hold (§5.3) is placed locally at trigger time and the cloud can only release it. On a memory warning, shorten retention, down to a floor of 25 s.

### 5.3 Holding and saving a moment — Deferred

> **Deferred.** For now a kept moment's window is cut out of the ring buffer in one pass when it is decided (§5.5). Per-window holds (sample references), writing live samples, extension and overlap sharing are not built. The design below is kept for when the decision can come too late for the buffer's retention.

1. Trigger at time T creates `Moment{fromMs = max(sessionStartMs, T - PRE_S*1000), toMs = T + POST_S*1000}`, default `PRE_S = POST_S = 15`, with status `held`.
2. The moment takes a **hold**: references to the buffered samples from the last keyframe at or before `fromMs` to now, plus every live sample until `toMs`. The references keep those samples alive after the ring buffer trims them. Overlapping holds share the same samples, so memory is the union of the windows, not their sum.
3. A skip answer releases the hold and nothing is written. When the moment is kept (button: at once; AI: cloud "keep", or the local fallback rule in §6), the clip writer saves it: an `AVAssetWriter` to `clips/{momentId}.mp4` with a passthrough video input (`outputSettings: nil`, `sourceFormatHint` from the first sample), so nothing is re-encoded, and an AAC input if audio is on. The session starts at the first sample's presentation time. If the decision arrives before `toMs`, the writer appends live samples until `toMs`; if it arrives later, the held samples are written in one pass.
4. When the writer has the last sample up to `toMs`, or the session pauses, it finishes the file, writes the sidecar JSON, and releases the hold. If the cloud has not answered by `toMs + 2000`, apply the local fallback rule (§6) to decide keep or release.
5. A new moment overlapping a held or still-writing moment by more than 5 s extends it, up to a 60 s cap.
6. A clip starts on a keyframe, so it may begin up to 2 s before `fromMs`; it ends at the last sample up to `toMs`. The agent trims it. Orientation is fixed per session, so the writer sets the video input's `transform` once, from the session orientation.

### 5.4 Crash and storage safety

- The ring buffer and the holds live in memory, so a crash or a kill loses up to 45 s of unsaved footage and any moment still held. Clips already saved are unaffected.
- On launch, delete any clip in `clips/` that has no sidecar JSON (it was being written), and mark moments still `held` as `released`.
- If free space is under 2 GB, stop AI-driven moments, keep button moments, and show a warning. Only saved clips use disk, so this should be rare.

### 5.5 Current implementation: window save

- A keep is decided at `triggerMs + POST_S + 2 s`, so `[T - PRE_S, T + POST_S]` (plus up to 2 s back to a keyframe) is inside the 45 s buffer at that moment. `PRE_S`/`POST_S` are `pre_s`/`post_s` in `detection_config.json`.
- The app calls the recorder's `writeClip(from:to:url:)`, which copies that window, from the keyframe at or before `fromMs`, to `trips/{tripId}/clips/{momentId}.mp4` by passthrough. The buffer is not emptied, so overlapping moments each get a full clip.
- The trip clock and the buffer share the capture session's host clock. The sidecar's `from_ms`/`to_ms` are the trip-clock times of the clip's first and last frame; it is written after the mp4.
- A release writes nothing. The `held` status is bookkeeping only: the footage is protected by the 45 s retention, not by references.
- If capture was interrupted mid-window and the clip no longer reaches back to its trigger, the clip is dropped and counted as a failed save. Stopping detection finalizes pending moments with the footage up to now.

## 6. Stage 1: on-phone signals and the escalation gate

A sampler takes a frame about every 2 s from the video stream, downscales to 640×360, and computes (no ML required):

| Signal | Computation |
|---|---|
| `sharpness` | Variance of Laplacian on a 160×90 grayscale copy |
| `exposure` | Mean luma; percent of pixels under 16 or over 240 |
| `change` | Mean absolute difference vs. the previous sample |
| `motion` | Mean of the last 3 `change` values, plus motion-sensor state |
| `dhash` | 64-bit difference hash |
| `forced` | True every 30th sample (about once a minute) so static scenery is still evaluated |

**Local score** `L = 0.4·changeSpike + 0.3·dwell + 0.2·quality + 0.1·novelty`, where `novelty` is the Hamming distance of `dhash` from recent escalated frames, normalized. Weights live in config. **Proposal.**

**Gate.** A sample becomes a candidate only if all hold:

1. Smoothed `L ≥ τ_escalate` (start at 0.55, tune on recorded footage).
2. It is a local peak among neighboring samples.
3. At least `COOLDOWN_S` (10) since the last escalation.
4. `dhash` Hamming distance ≥ 10 from the last escalated frame.
5. The cloud budget allows it (§8.3), and the user allowed cloud analysis.

A `forced` sample skips rules 1 and 2 but must pass 3 to 5, and counts as an escalation for cooldown, budget and the gate test (§12.1). Rule 2 needs the next sample to confirm a peak, so a candidate is known one sample interval (2 s) after its frame.

When a candidate passes the gate, the phone immediately **holds the moment window in memory (speculative hold, §5.3)** and sends the packet to the cloud. A "skip" answer releases the hold and nothing is written to disk.

**Local fallback.** If the cloud is unavailable, over budget, or consent is off, save locally when `L ≥ 0.85` (`source = local_fallback`); otherwise release. The Bluetooth button always saves.

## 7. Bluetooth button (FR-009)

- **Proposal:** use an off-the-shelf Bluetooth shutter remote, which presents as a keyboard or volume key. The app receives it as a hardware key event in the foreground, for example through `AVCaptureEventInteraction` or by observing volume changes. This must be verified with the screen at brightness 0 and a locked-to-foreground app.
- **Alternative:** a custom BLE device using Core Bluetooth with a defined characteristic, if no off-the-shelf remote works.
- On press: create a moment with `source = button` at the press time, hold and save `[T−15 s, T+15 s]` (§5.3), and give a haptic confirmation (`UIImpactFeedbackGenerator`). Button moments bypass the gate, cooldowns and budgets and are never released by the cloud.
- Button moments are sent to the cloud later, off the critical path, only to get a description and category.

## 8. Cloud backend and AI

**Proposal:** Python 3.11, FastAPI, one process. Holds the model API key in `.env`; the app never sees it.

### 8.1 Endpoints

| Endpoint | Request | Response |
|---|---|---|
| `POST /v1/evaluate` | multipart: 3 JPEG frames (512 px long edge, `t−4 s`, `t−2 s`, `t`) + JSON context | Stage 2 output (§8.2) |
| `GET /healthz` | none | `{ok: true}` |

**Context** sent with `/v1/evaluate`: destination, trip type, style, trip length, local score and signals, and the descriptions of every moment saved so far this trip, for redundancy. No names, no location coordinates, no device identifiers beyond a random install id.

**Auth.** **Proposal:** a bearer app token set at build time for the hackathon. This is weak because it can be extracted from the app; before any public release replace it with per-install tokens and App Attest.

### 8.2 Stage 2 — evaluation

The model is a fast vision model whose ID is config. Each request makes one call; there is no escalation to a stronger model.

Output, enforced with tool use or a JSON schema and validated with Pydantic:

```json
{
  "event_type": "scenery | landmark | activity | food | social | other",
  "matched_preferences": ["scenery"],
  "save_decision": "save | skip",
  "best_frame_index": 2,
  "window_hint_s": {"pre": 15, "post": 15},
  "description": "≤ 20 words, only what is visible",
  "reason": "≤ 25 words"
}
```

**Prompt rules:** judge only what is visible; decide save or skip as a whole judgment, with no scores; never name a place unless recognizable or in the destination; prefer `skip` for transit, screens, and redundant views of a saved moment; skip when unsure; never identify people ("a person", "friends"). Trip type and style shape what counts as interesting (a honeymoon favors couple and scenic moments).

**Keep rule:** keep when `save_decision = save`. The model makes the call itself; there is no score or threshold. Kept ai clips carry the phone's local score L as their `score` for ranking in the edit.

**Failure handling:** the phone times out at 8 s, retries once on invalid JSON, then uses the local fallback (§6). Maximum 2 evaluations in flight; the queue holds 3 and drops the oldest. A dropped request's hold stays in place and is resolved by the local fallback when the moment finalizes (§5.3).

### 8.3 Budget and pacing

A token bucket per trip: capacity 5, refill 1 per 30 s, with a hard cap of 100 calls per recording hour. **Proposal:** caps count recording hours, not `lengthDays`, because a multi-day trip may record only a few hours a day; a per-trip spend cap sits on top (open, §14). As the bucket drains, the gate tightens: `τ_escalate = τ_base + 0.20·(1 − tokens/capacity)`. The backend enforces the caps too, so a modified app cannot overspend. A `DEMO_MODE` profile shortens cooldowns to 5 s and lowers `τ_base` to 0.45.

## 9. Post-trip editing

Triggered when the trip ends and all clips are finalized. A Claude agent makes the whole video: it selects the moments, trims and edits them, writes its own Remotion composition, renders it, checks it and submits it. It runs on the Claude Agent SDK (TypeScript) inside the render service (`render/`). Plan: `docs/agentic-video-generation.md`.

### 9.1 Pre-pass on the phone

Drop near-duplicate clips (best-frame `dhash` distance) and pick a best sub-window per clip (sharpness and stability from the sampled signals), sent as `proposed_in_s`/`proposed_out_s`. Button clips always go; past `max_clips` the lowest-scored others are dropped.

**Target duration (Proposal):** 30–60 s in the MVP regardless of trip length. Button moments win over the target (PRD FR-009): the **effective target** is the larger of the preset target and (button moments × the preset's shortest clip length + end card). The agent is told to fill button moments first, cut them toward the shortest clip length when space is short, and add AI moments only into the time left.

### 9.2 The agent

- **Flow:** the phone re-encodes every candidate clip whole at 720p and uploads them with the trip context and clip table to `POST /v1/agent`. The agent looks at the clips by sampling frames, plans the edit, writes the composition, previews stills, renders, checks the file, and calls `submit` with the result (length, title, and where each moment lands). The phone polls the job, fetches the result, downloads the MP4 and checks it plays and its duration matches the result (§10). Review's moment list comes from the result.
- **Rules the server enforces on `submit`:** every button moment is in the video, moment ids exist, and the length is within ±10 % of the effective target (§9.1) and matches the rendered file. The prompt carries the other rules: chronological order, title only from the destination, trip type and date, no invented events, no identifying people. The output size and fps come from the style preset.
- **Limits (config):** `AGENT_MAX_TURNS`, `AGENT_TIMEOUT_S` (480 s), `AGENT_MAX_RENDERS` and `AGENTS_PER_TRIP`. The agent has only file tools confined to its job workspace and our own tools (look at a clip, preview frames, render, submit): no shell and no network. Its composition loads clips and music only from the workspace.
- **Failure:** any error, timeout, failed job or failed check ends in an error on the Processing screen with Retry. There is no fallback renderer.
- **Time:** an agent loop plus a full render will likely take 3 to 8 minutes, over the 2-minute target; the Processing screen says it takes a few minutes. An agent job holds a render slot for its whole run.
- Contracts: `contracts/agent_request.schema.json`, `agent_result.schema.json`, `render_job.schema.json` and the `/v1/agent` section of `contracts/README.md`.

| Preset | Target length | Clip length | Transition | Aspect | Music |
|---|---|---|---|---|---|
| Cinematic | 45–60 s | 4–8 s | 0.5–0.8 s fade | 16:9 | Ambient, −14 dB |
| Reels | 30 s | 1.5–3 s | Hard cuts | 9:16 | Upbeat, −10 dB |
| Documentary | 60 s | 5–10 s | Dissolve | 16:9 | Low bed, −20 dB |
| Vlog | 45–60 s | 3–8 s | Hard cuts | 16:9 | Light, original audio kept |

All four presets allow captions; each style draws them its own way (`render/src/remotion/styles/`, which the agent imports). Presets are config files the agent gets verbatim. Uploading needs the app in the foreground, so the Processing screen keeps the screen awake.

Music tracks are bundled with the app and synced to the render service. Licensing is open.

## 10. App-facing states and screens

**Trip states:** `CREATED → RECORDING ⇄ PAUSED → FINALIZING → PLANNING → RENDERING → COMPLETED`, with `ERROR` reachable from any state with an `errorStage` and a retry action.

| Transition | Trigger | Guard |
|---|---|---|
| CREATED → RECORDING | Start Recording | Camera permission granted; orientation correct; brightness and idle timer set |
| RECORDING → PAUSED | Pause, interruption, backgrounding, thermal critical, low battery | Session closed as in §4.4 |
| PAUSED → RECORDING | Resume (user action only) | Same guards as Start Recording |
| RECORDING or PAUSED → FINALIZING | End Trip | Capture stopped, ring buffer cleared; pending moments finalized |
| FINALIZING → PLANNING | All moments finalized | At least 1 clip, else ERROR(no_moments) |
| PLANNING → RENDERING | Pre-pass done; upload to the agent starts | Render service configured, else ERROR |
| RENDERING → COMPLETED | Agent job completes and the downloaded file plays | "Video ready" only after this check |

**Screens:** Onboarding (style, destination, trip type, length, permissions, mounting guide), Recording (black, status on wake with Pause and End Trip), Paused (Resume, End Trip), Processing (finalizing, then the agent job's progress), Review (player, save or share, moment list with button moments marked, optional feedback). Review feedback adjusts saved preferences.

**Status banner (on wake):** Recording; Paused (with reason); Thermal limit reached; Cloud analysis limited, button still works; Processing; Video ready; Error with retry.

## 11. Non-functional requirements

### 11.1 Timing budget (trigger to held footage)

| Step | Target | Worst case |
|---|---|---|
| Sample interval | 2 s | 2 s |
| Peak confirmation (next sample, §6 rule 2) | 2 s | 2 s |
| On-phone gate | 30 ms | 100 ms |
| Hold placed | immediate | immediate |
| **Time to hold** | **~4 s** | **~4.1 s** |
| Cloud decision (off critical path) | 2–4 s | 8 s, then local fallback |

Required buffer is the 15 s pre-roll plus about 4 s plus up to 2 s back to a keyframe, so 45 s gives wide headroom. Because holds are deferred (§5.3), the cloud answer must arrive before the footage ages out of the buffer; the decision is taken at trigger + POST_S + 2 s, which is 17 s of the 45 s.

### 11.2 Reliability

- Capture never depends on the network, and cloud failure only triggers the local fallback.
- Crash restart deletes partial clips, releases held moments and restores brightness (§5.4).
- Disk, thermal and battery guards in §4.1, §5.4.

### 11.3 Security and privacy (PRD §10)

- Recording starts only after an explicit tap; a recording indicator is visible whenever the status view is shown, and iOS shows its own camera indicator.
- During the trip only 512 px sample frames leave the phone.
- **Video (§9):** when the trip ends, every kept clip, whole, is uploaded at 720p to the render service. The clips and the agent's workspace are deleted when the job ends, and the output after it is downloaded or `RENDER_TTL_S` (15 min) after the job ends, whichever comes first. Frames the agent looks at go to the model API under the same provider terms as Stage 2 frames. Logs hold ids, timings, turn and render counts, cost and error codes, never video or frames. This happens whatever the "Allow cloud analysis" setting, and the consent screen must say that kept clips are uploaded for editing and then deleted.
- Model API keys live in the backend `.env`. The app holds only the app token.
- Footage that is not selected is never written to disk: it leaves the in-memory ring buffer within `BUFFER_RETENTION_S`. Backend logs must not store frames; provider retention terms must be checked and shown to the user.
- "Allow cloud analysis" is asked at setup and covers detection: when off, only the local fallback and the button keep moments. The video is still made in the cloud.
- Audio is off by default. Prompts forbid identifying people.

## 12. Testing, gates, risks

### 12.1 Technical gates (no hour marks; the schedule is open)

1. **Capture:** 10 minutes of 1080p30 capture and encoding into the ring buffer with the screen at 0 brightness, no dropped frames, memory use flat, thermal state not above `.fair`.
2. **Battery:** the spike (below) gives battery and heat numbers at a fixed 30 fps. (Tier floors and mid-session rate changes wait for §4.3.)
3. **Buffer:** a button press at T yields a clip spanning at least `T−15 s` to `T+15 s`, checked with a burned-in clock; samples older than 45 s are gone from the buffer, and no unselected footage is on disk.
4. **Button:** a Bluetooth remote press is received with the screen at 0 brightness, in the foreground, with the haptic.
5. **Setup flow:** a new user reaches Start Recording in under 2 minutes; choices persist.
6. **Detection:** on a replayed 10-minute walk, the gate escalates at most 10 % of samples (forced samples included) and the cascade saves 3 of 3 scripted moments.
9. **Pause and resume:** a phone call mid-trip pauses it; resuming continues the same trip, and the final video includes moments from both sessions.
10. **Button over budget:** 12 button presses on a Reels trip all appear in the video, which runs past 30 s.
7. **Video:** ending a trip yields a valid 30–60 s video with no manual step, in under 2 minutes.
8. **Repeatability:** three consecutive end-to-end runs succeed.

### 12.2 Test plan

- **Unit (XCTest):** trip state machine (pause and resume), gate logic, budget bucket, ring buffer (append, trim, keyframe lookup), holds and clip writing (overlapping and pending holds, release on skip, finalize on pause), pre-pass, the agent client and coordinator (effective target), merging.
- **Backend (pytest):** schema validation, budget enforcement, error paths.
- **Replay harness:** recorded sample folders with labeled "should save" timestamps; reports precision, recall and calls per minute per threshold set.
- **Personalization check:** the same replay with "honeymoon" vs. "school" produces different top moments.
- **Fault injection:** block the network, fill the disk, kill the app mid-trip, take a phone call, lower the battery, run hot.
- **Agent matrix:** 1, 3 and 10 clips; with and without audio; both aspect ratios (`render/scripts/agent-smoke.sh`, spends API money).

### 12.3 The first spike (throwaway)

A small test app that records at 30 fps for 10 minutes, screen at 0 brightness, logging battery level, thermal state and memory while encoding into the ring buffer and saving a 30 s passthrough clip every minute. Run on a real iPhone. It answers the battery question and the §5.1 and §5.3 assumptions: a clip written by passthrough starts on a keyframe and plays with audio in sync, and memory stays flat. (The mid-session rate-change test returns with §4.3.)

### 12.4 Replay mode and the demo (Decided: pre-recorded footage; mechanism Proposal)

The demo's final video is made from pre-recorded footage (Decided). The app has a **replay mode** in debug builds: an `AVAssetReader` feeds a pre-recorded walk video (and its recorded motion log) into the same pipeline in place of the camera. Everything after capture (buffer, Stage 1, cloud, button, edit, render) runs unchanged, so the demo shows the real system. The replay harness in §12.2 uses the same path.

Demo script: (1) run onboarding live, (2) start replay of a 3–5 minute walk recorded beforehand on the chest mount with `DEMO_MODE` on, (3) press the Bluetooth button live during it, (4) end the trip and show the processing screen, (5) play the finished video with the button moment marked. Have a finished video from the same replay ready in case the network fails.

### 12.5 Risks

| Risk | Mitigation |
|---|---|
| Passthrough clip does not play or loses audio sync | Re-encode the held samples when saving (more battery, only at save time) |
| Ring buffer memory grows or the app is killed for memory | Compressed samples only, shorter retention on memory warning (§5.2) |
| Bluetooth remote not received with a dark screen | Test early; custom BLE fallback |
| User backgrounds or locks the app | Foreground-only design, pause with a notification, clear onboarding message |
| Phone worn wrong (pocket, wrong orientation) | Mounting guide in onboarding, orientation check with a haptic prompt |
| Live demo fails (network, venue) | Replay mode and a pre-rendered backup video (§12.4) |
| Phone overheats | Thermal caps and finalize |
| Cloud latency or outage | Speculative hold and local fallback |
| Over-escalation drains budget | Peaks, cooldowns, adaptive threshold, server caps |
| Agent job too slow, fails or the service is down | Measure early; Retry on the Processing screen; a pre-rendered backup video for the demo (§12.4) |
| Globe map takes too long | MapKit fallback |
| App token extractable | Acceptable for the demo; per-install tokens later |

## 13. Contracts

`contracts/` must be defined before the app and backend are built in parallel, in its own PR. Messages defined: evaluate request (context) and response (Stage 2 output), agent request and result, render job, style presets, error shape (code, message, retryable), and the auth header. The earlier contracts plan for the glasses design is obsolete.

## 14. Open questions

- Which frontier model provider and model IDs, and the per-trip spend cap?
- Which test devices are available? They must be iPhone 11 or later running iOS 26.
- Does our chest mount's clamp rotate to portrait and landscape? Record the demo walk in the orientation of the style we demo.
- Which Bluetooth button hardware, and does it present as a key or as BLE?
- What does one video cost (agent model calls with images plus the render, §9.2), and is `AGENTS_PER_TRIP` the right cap?
- How long does a video take from upload to download on Fly.io (4 dedicated vCPU shared with the backend), and is that acceptable to users behind a "takes a few minutes" Processing screen?
- Does our 4-person team need a Remotion company license (free for individuals and companies of up to 3)?
- Does the user need rendering to continue if they leave the app?
- Are location and audio signals worth including in the MVP?
- Who produces the four style sample clips, and which music tracks are licensed?
- Native Swift is assumed. Is anyone on the team unable to work in it?
