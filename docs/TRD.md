# Roamory — Technical Requirements Document

Oct 23, 2026 · v2.1 (iPhone pivot; iOS 26 target). Replaces v1.0 (glasses + Raspberry Pi), which is discarded.

> **How to read this document.** It implements `docs/PRD.md` v2.0. Choices that come from the PRD's **(Decided)** items are stated plainly. Everything else is a **proposal** by the author, to be confirmed or changed; Section 14 lists what is open. iOS API names are from the author's knowledge and must be checked against current Apple documentation during the first spike.

## 1. Overview

Roamory is an iPhone app that films a trip with the screen dark, keeps the moments that matter in a rolling buffer, and builds a highlight video the user reviews in the app. Cloud AI (a frontier vision model) selects the moments.

**In scope:** interactive onboarding, camera capture at a fixed 30 fps, in-memory ring buffer and moment saving, Bluetooth button, cloud moment selection, edit planning, video rendering, in-app review.

**Deferred:** adaptive frame rate (§4.3, PRD FR-008); per-window holds and partial clips (§5.3).

**Out of scope (PRD §3.3):** extra hardware, Android, background camera capture, manual timeline editing, multi-user features.

**Design constraints that drive most decisions**

- Recording never waits on the network or AI. The phone holds footage in memory and saves it locally; the cloud only says "keep" or "skip". Footage that is not selected is never written to disk.
- Full-resolution video stays on the phone. Only small sample frames go to the cloud. The one exception is the optional cloud render engine, which uploads the trimmed selected clips and deletes them after (§9.2, §11.3).
- The camera cannot run in the background on iOS, so the app stays in the foreground, with the screen at brightness 0 and auto-lock disabled, for the whole trip.
- Frontier model calls are slow (1–5 s) and metered, so cheap on-phone checks decide when to ask.
- Rendering is deterministic. The LLM produces a JSON edit spec; the phone executes it.

| Term | Meaning |
|---|---|
| Session | One continuous recording run; a trip has one or more (PRD FR-007b) |
| Ring buffer | An in-memory queue of the last `BUFFER_RETENTION_S` of encoded video samples (and audio, if enabled); nothing in it is on disk until a moment is saved (§5) |
| Hold | References to the buffered samples around a moment, kept so they outlive the ring buffer's trimming (§5.3) |
| Trip clock | Wall-clock milliseconds since trip start, `t_ms`; it keeps running while paused, so sessions leave gaps |
| Stage 1 | The on-phone signals and escalation gate (§6) |
| Stage 2 | The cloud evaluation (§8.2): 2a is the fast model, 2b the strong one |
| Tier | A camera frame-rate level (for example 30, 15, 10 fps); deferred with §4.3 |
| Sample | A downscaled JPEG frame used for on-phone checks and cloud evaluation |
| Candidate | A sample that passed the on-phone gate and is sent to the cloud |
| Moment | A kept window `[T−pre, T+post]` around a trigger time T |
| Clip | The finalized video file for one moment |
| Edit spec | JSON plan from the cloud planner that the on-phone renderer executes |

## 2. System architecture

Two components: the **iOS app**, which does everything except the model calls, and a thin **cloud backend** that holds the model API key and calls the frontier model. A third, optional component, the **render service** (`render/`, Remotion), renders the highlight video in the cloud when that engine is chosen (§9.2).

```text
 iPhone app                                   Cloud backend (FastAPI)
 ┌──────────────────────────────┐            ┌─────────────────────┐
 │ Onboarding UI (SwiftUI)      │            │ POST /v1/evaluate   │
 │ Capture (fixed 30 fps)       │  frames    │   → Stage 2 model   │
 │ Ring buffer + clip writer    │ ────────►  │ POST /v1/plan       │
 │ On-phone gate (signals)      │  keep/skip │   → planner model   │
 │ Bluetooth button             │ ◄────────  │ GET  /healthz       │
 │ Edit-spec renderer (AVFound.)│            └─────────────────────┘
 │ Review UI                    │                    │
 └──────────────────────────────┘                    ▼
        │  trimmed clips ▲ MP4              Frontier vision model API
        ▼  (optional)    │
 ┌──────────────────────────────┐
 │ Render service (Remotion)    │
 │ POST /v1/render, poll, video │
 └──────────────────────────────┘
```

- **Proposal:** the backend stores no trip data in the MVP; all trip data lives on the phone. Its only state is in-memory call counters per trip for the budget caps (§8.3), which reset if the process restarts. That is acceptable for the demo.
- **Proposal:** the video is rendered on the phone, which settles PRD open question 3 provisionally. It avoids uploading full video and keeps footage private. Revisit if render time misses the 2-minute target.
- **Decided:** Remotion in the cloud is an optional second engine for richer motion graphics (§9.2). Only the trimmed ranges the edit spec uses are uploaded, and they are deleted when the job ends. AVFoundation on the phone stays the default and the fallback.
- **Decided:** the backend and the render service run together in one Fly.io app (`cloud/`, settings in `cloud/fly.toml`) on one machine (the budget counters and render jobs are in memory) that never auto-stops, so renders continue between polls. A Caddy proxy routes `/v1/render*` to the render service and the rest to the backend. Google Cloud was dropped. Redeploying restarts both, which resets the budgets and drops in-flight renders. Laptop hosting (`scripts/dev.sh`) still works for development.
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
| `Edit/` | Plan request, validation, fallback planner, renderer |
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
| `Evaluation` | `id`, `momentId`, `tier` (2a/2b), `latencyMs`, `response` (JSON), `s2`, `error` |
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
6. A clip starts on a keyframe, so it may begin up to 2 s before `fromMs`; it ends at the last sample up to `toMs`. The planner trims it. Orientation is fixed per session, so the writer sets the video input's `transform` once, from the session orientation.

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
| `POST /v1/plan` | JSON clip table + 4 thumbnails per clip (384 px) | Edit spec (§9.1) |
| `GET /healthz` | none | `{ok: true}` |

**Context** sent with `/v1/evaluate`: destination, trip type, style, trip length, local score and signals, and the last 5 saved-moment descriptions for redundancy. No names, no location coordinates, no device identifiers beyond a random install id.

**Auth.** **Proposal:** a bearer app token set at build time for the hackathon. This is weak because it can be extracted from the app; before any public release replace it with per-install tokens and App Attest.

### 8.2 Stage 2 — evaluation

The model is a vision model whose ID is config. **Proposal:** a fast tier handles every request and a strong tier only runs when the fast tier answers `uncertain` or its score lands within ±0.08 of the threshold.

Output, enforced with tool use or a JSON schema and validated with Pydantic:

```json
{
  "event_type": "scenery | landmark | activity | food | social | other",
  "matched_preferences": ["scenery"],
  "preference_alignment": 0.0,
  "visual_interest": 0.0,
  "significance": 0.0,
  "visual_quality": 0.0,
  "save_decision": "save | skip | uncertain",
  "best_frame_index": 2,
  "window_hint_s": {"pre": 15, "post": 15},
  "description": "≤ 20 words, only what is visible",
  "reason": "≤ 25 words"
}
```

**Prompt rules:** score only what is visible; never name a place unless recognizable or in the destination; prefer `skip` for transit, screens, and redundant views of a saved moment; return `uncertain` rather than guessing; never identify people ("a person", "friends"). Trip type and style shape what counts as interesting (a honeymoon favors couple and scenic moments).

**Final score** uses these weights (config), with novelty from the phone:

`S2 = 0.35·pref + 0.25·interest + 0.20·significance + 0.10·quality + 0.10·novelty`

Save when `save_decision = save` and `S2 ≥ 0.60`, or `S2 ≥ 0.75` regardless. Weights and thresholds are config.

**Failure handling:** the phone times out at 8 s, retries once on invalid JSON, then uses the local fallback (§6). Maximum 2 evaluations in flight; the queue holds 3 and drops the oldest. A dropped request's hold stays in place and is resolved by the local fallback when the moment finalizes (§5.3).

### 8.3 Budget and pacing

A token bucket per trip: capacity 5, refill 1 per 30 s, with hard caps per recording hour of 100 fast and 15 strong calls. **Proposal:** caps count recording hours, not `lengthDays`, because a multi-day trip may record only a few hours a day; a per-trip spend cap sits on top (open, §14). As the bucket drains, the gate tightens: `τ_escalate = τ_base + 0.20·(1 − tokens/capacity)`. The backend enforces the caps too, so a modified app cannot overspend. A `DEMO_MODE` profile shortens cooldowns to 5 s and lowers `τ_base` to 0.45.

## 9. Post-trip editing

### 9.1 Planning

Triggered when the trip ends and all clips are finalized.

1. **Pre-pass on the phone:** drop near-duplicate clips (best-frame `dhash` distance), pick a best sub-window per clip (sharpness and stability from the sampled signals), and make 4 thumbnails per clip at 384 px.
2. **Cloud planner:** `POST /v1/plan` with the clip table (id, times, category, description, score, proposed trims, source), thumbnails, the style preset, trip type, and target duration. It returns an **edit spec**:

```json
{
  "trip_id": "t_123",
  "style": "cinematic",
  "output": {"width": 1920, "height": 1080, "fps": 30},
  "title": {"text": "Kyoto", "subtitle": "October 2026", "duration_s": 2.5},
  "clips": [
    {"moment_id": "m_07", "in_s": 11.0, "out_s": 17.5,
     "transition_in": "fade", "transition_s": 0.5,
     "speed_ramp": {"from": 0.25, "to": 1.0, "over_s": 1.5},
     "caption": null}
  ],
  "music": {"track": "cinematic_01", "gain_db": -14, "duck_original_audio": true},
  "end_card": {"text": "Made with Roamory", "duration_s": 2.0}
}
```

3. **Validate on the phone:** every clip id exists, trims fall inside clip bounds, every button moment is included, total duration is within ±10 % of the effective target (below), and captions use only the destination, trip type, or Stage 2 descriptions (PRD FR-015). On failure, a greedy fallback planner takes the top-scored clips (button moments first) until the duration is filled, orders them chronologically, and applies the preset defaults.

**Target duration (Proposal):** 30–60 s in the MVP regardless of trip length. Button moments win over the target (PRD FR-009): the **effective target** is the larger of the preset target and (button moments × the preset's shortest clip length + title + end card). The planner and the fallback both fill button moments first, cut them toward the shortest clip length when space is short, and add AI moments only into the time left.

### 9.2 Rendering (on the phone; optional cloud engine)

**Proposal:** `AVMutableComposition` assembles the trimmed clips; `AVMutableVideoComposition` handles scaling or cropping and cross-fades; titles and captions use the Core Animation tool; `scaleTimeRange` implements speed-ramps; `AVMutableAudioMix` applies music gain and ducking with volume ramps; `AVAssetExportSession` writes the MP4.

| Preset | Target length | Clip length | Transition | Aspect | Music |
|---|---|---|---|---|---|
| Cinematic | 45–60 s | 4–8 s | 0.5–0.8 s fade | 16:9 | Ambient, −14 dB |
| Reels | 30 s | 1.5–3 s | Hard cuts | 9:16 | Upbeat, −10 dB |
| Documentary | 60 s | 5–10 s | Dissolve | 16:9 | Low bed, −20 dB, captions |
| Vlog | 45–60 s | 3–8 s | Hard cuts | 16:9 | Light, original audio kept |

Presets are config files sent to the planner verbatim. If rendering with transitions fails, retry once with hard cuts. Rendering needs the app in the foreground, so the processing screen keeps the screen awake. **Performance target:** a 30–60 s video in under 2 minutes on a recent iPhone, to be measured.

Music tracks are bundled with the app. Licensing is open.

**Cloud engine (Decided, optional): Remotion.** The render service (`render/`, Node 22, Remotion) renders the whole video from the same edit spec, for motion graphics Core Animation can't do well (kinetic titles, lower thirds, animated transitions). The LLM still only produces JSON and rendering stays deterministic.

- It runs only when the edit config's `render_engine` is `remotion` and "Allow cloud analysis" is on (§11.3).
- The phone trims each clip to `[in_s, out_s]` (re-encoded, frame-exact), uploads the trimmed files with a **rebased** edit spec to `POST /v1/render`, polls the job, downloads the MP4, and runs the same playable and duration check as a local render (§10).
- Any error, timeout or failed job falls back to the AVFoundation renderer, so the video always completes. `generated_video.json` records which engine made it.
- Both engines test against the golden timelines in `contracts/examples/timeline_*.json`, so Review's moment times match either render.
- Contracts: `contracts/render_request.schema.json`, `render_job.schema.json` and the `/v1/render` section of `contracts/README.md`.

## 10. App-facing states and screens

**Trip states:** `CREATED → RECORDING ⇄ PAUSED → FINALIZING → PLANNING → RENDERING → COMPLETED`, with `ERROR` reachable from any state with an `errorStage` and a retry action.

| Transition | Trigger | Guard |
|---|---|---|
| CREATED → RECORDING | Start Recording | Camera permission granted; orientation correct; brightness and idle timer set |
| RECORDING → PAUSED | Pause, interruption, backgrounding, thermal critical, low battery | Session closed as in §4.4 |
| PAUSED → RECORDING | Resume (user action only) | Same guards as Start Recording |
| RECORDING or PAUSED → FINALIZING | End Trip | Capture stopped, ring buffer cleared; pending moments finalized |
| FINALIZING → PLANNING | All moments finalized | At least 1 clip, else ERROR(no_moments) |
| PLANNING → RENDERING | Valid edit spec or fallback plan | |
| RENDERING → COMPLETED | Export succeeds and the file plays | "Video ready" only after this check |

**Screens:** Onboarding (style, destination, trip type, length, permissions, mounting guide), Recording (black, status on wake with Pause and End Trip), Paused (Resume, End Trip), Processing (finalizing, planning, rendering progress), Review (player, save or share, moment list with button moments marked, optional feedback). Review feedback adjusts saved preferences.

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
- Only 512 px sample frames and 384 px thumbnails leave the phone. Full video stays on the device.
- **Exception (cloud render engine, §9.2):** when Remotion is chosen, the trimmed ranges of the selected clips are uploaded to the render service. It deletes the uploaded clips when the job ends, and the output after it is downloaded or `RENDER_TTL_S` (15 min) after the job ends, whichever comes first. Its logs hold ids, timings and error codes, never video. This needs "Allow cloud analysis" on, and the consent screen must say that selected clips are uploaded for rendering and then deleted.
- Model API keys live in the backend `.env`. The app holds only the app token.
- Footage that is not selected is never written to disk: it leaves the in-memory ring buffer within `BUFFER_RETENTION_S`. Backend logs must not store frames; provider retention terms must be checked and shown to the user.
- "Allow cloud analysis" is asked at setup. When off, only the local fallback and the button work.
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

- **Unit (XCTest):** trip state machine (pause and resume), gate logic, budget bucket, ring buffer (append, trim, keyframe lookup), holds and clip writing (overlapping and pending holds, release on skip, finalize on pause), edit-spec validator (effective target), merging.
- **Backend (pytest):** schema validation, budget enforcement, error paths.
- **Replay harness:** recorded sample folders with labeled "should save" timestamps; reports precision, recall and calls per minute per threshold set.
- **Personalization check:** the same replay with "honeymoon" vs. "school" produces different top moments.
- **Fault injection:** block the network, fill the disk, kill the app mid-trip, take a phone call, lower the battery, run hot.
- **Render matrix:** 1, 3 and 10 clips; with and without audio; both aspect ratios.

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
| On-device render too slow | Measure early; fall back to a hard-cut preset or cloud render |
| Globe map takes too long | MapKit fallback |
| App token extractable | Acceptable for the demo; per-install tokens later |

## 13. Contracts

`contracts/` must be defined before the app and backend are built in parallel, in its own PR. Messages to define: evaluate request (context) and response (Stage 2 output), plan request, edit spec, style presets, error shape (code, message, retryable), and the auth header. The JSON in §8.2 and §9.1 is the starting point. The earlier contracts plan for the glasses design is obsolete.

## 14. Open questions

- Which frontier model provider and model IDs, and the per-trip spend cap?
- Which test devices are available? They must be iPhone 11 or later running iOS 26.
- Does our chest mount's clamp rotate to portrait and landscape? Record the demo walk in the orientation of the style we demo.
- Which Bluetooth button hardware, and does it present as a key or as BLE?
- Is on-phone rendering fast enough, or must it move to the cloud?
- Is the Remotion render service on Fly.io (2 shared vCPU, which throttle after a burst, shared with the backend, decided in §2) fast enough (about 1800 frames for 60 s at 1080p30, plus the upload) for the 2-minute target?
- Does our 4-person team need a Remotion company license (free for individuals and companies of up to 3)?
- Does the user need rendering to continue if they leave the app?
- Are location and audio signals worth including in the MVP?
- Who produces the four style sample clips, and which music tracks are licensed?
- Native Swift is assumed. Is anyone on the team unable to work in it?
