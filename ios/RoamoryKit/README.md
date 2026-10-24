# RoamoryKit

Phone-side logic as a local Swift package: the Edit pipeline (TRD §9, Phase 2 of the video generation plan) and Stage 1 moment detection (TRD §6). The Edit side has Codable contract mirrors, the edit-spec validator, the fallback planner, the pre-pass, the AVFoundation renderer, the `/v1/plan` client and `EditCoordinator`. It has no app target of its own, so it builds and tests on macOS as well as iOS 26.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Edit/` | Models, `EditSpecValidator`, `FallbackPlanner`, `PrePass`, `Renderer` + `TitleOverlay`, `ClipTrimmer`, `EditPlanner`, `EditCoordinator`, `RenderLabView` (debug) |
| `Sources/RoamoryKit/Signals/` | Stage 1 detection: frame signals, local score, escalation gate, `MomentDetector` |
| `Sources/RoamoryKit/Trip/` | A finished recording to clips: `FileDetection` (runs a video file through `MomentDetector`), `CollectingHolder`, `ClipExtractor` (kept moments to `clips/{id}.mp4` + sidecar), `TripSettings`, `TripPipeline` (recording → clips → `EditCoordinator`, in `Documents/Trips/{tripId}/`) |
| `Sources/RoamoryKit/Cloud/` | `PlanClient` (`POST /v1/plan`, multipart), `RemoteRenderClient` (`/v1/render`, Remotion), `POST /v1/evaluate` contract mirrors and `EvaluateClient` |
| `Sources/RoamoryKit/Config/` | `EditConfig` (`Resources/edit_config.json`), `DetectionConfig` (`Resources/detection_config.json`) and bundled-file lookup |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `edit_config.json`, placeholder music beds, 2 s black end-card clips, RenderLab sample clips |
| `scripts/` | `sync-contracts.sh` (copy the presets after a contract change), `make-placeholder-assets.sh` (regenerate the media with ffmpeg) |

## Add it to the app

The Roamary app already links it as a local package (File > Add Package Dependencies… > Add Local… > `ios/RoamoryKit`). In Debug builds the app's top-right menu opens `RenderLabView()`. It renders the bundled samples, or any `.mp4` you put in the app's Documents folder. That folder shows in Files once the app's Info.plist has `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.

The cloud planner is used only when the app's Info.plist has `RoamoryAPIBaseURL` and `RoamoryAppToken`. Set them from an untracked `.xcconfig`, never commit the token. Without them, or with cloud analysis off, the fallback planner runs.

```swift
let coordinator = EditCoordinator(
    trip: trip, clips: clips, outputDirectory: tripFolder.appending(path: "video"),
    presets: try .bundled(), config: try .bundled(),
    service: PlanClient.fromBundle(config: try .bundled()),
    remoteRenderer: RemoteRenderClient.fromBundle(config: try .bundled(), trip: trip)
)
await coordinator.run()   // phase: planning -> rendering(progress) -> completed / error; run() again to retry
```

The video renders on the phone with AVFoundation unless `edit_config.json` has `"render_engine": "remotion"`, the Info.plist has `RoamoryRenderBaseURL` (same `RoamoryAppToken`) and cloud analysis is on. Then `RemoteRenderClient` trims the clips the spec uses, uploads them to the render service (`render/`), polls the job and downloads the MP4. On any error, or after `remote_render_timeout_s`, the coordinator renders on the phone instead; `GeneratedVideo.renderEngine` records which engine made the file. In Render Lab, the engine picker's "Both" renders each style on each engine to compare times.

`ClipInfo(sidecar:moment:tripFolder:)` builds the input from a `clips/{id}.json` sidecar plus the Moment record's fields.

### From a recording

The app (`ios/Roamary`) makes the video from a finished recording with `TripPipeline`, until the live rolling buffer exists. It moves the file into `Documents/Trips/{tripId}/source.*`, runs it through `MomentDetector` (`FileDetection`, with the marked moments as button presses), cuts each kept moment into `clips/{id}.mp4` plus its sidecar (`ClipExtractor`, windows from `pre_s`/`post_s`, merged up to `max_clip_s`), then runs `EditCoordinator` into `video/`:

```swift
let pipeline = TripPipeline(settings: TripSettings.load())
await pipeline.start(video: recordingURL, buttonPressesMs: marks)
// phase: finding(progress) -> editing (pipeline.coordinator has planning/rendering/completed/error) or failed
await pipeline.retry()                    // after an error
await pipeline.rerender(style: .reels)    // same clips, another style
```

`EvaluateClient.fromBundle` reads the same Info.plist keys as the planner; without them, or with cloud analysis off, only moments with a local score of at least `local_fallback_min` are kept besides marked ones, so a recording with no marks usually ends in `no_moments`. `detector-replay` uses the same `FileDetection` loop.

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac, including real renders of the sample clips.
- `xcodebuild test -scheme RoamoryKit -destination 'platform=iOS Simulator,name=iPhone 17'` runs on iOS.

Tests read `contracts/examples` straight from the repo. `ContractsTests` fails if the bundled presets drift from `contracts/style_presets.json`; run `scripts/sync-contracts.sh`.

## Replay

`detector-replay` runs a recorded walk through Stage 1 detection on the Mac (TRD §12.1 gate 6, §12.4):

```sh
swift run detector-replay walk.mp4 --labels labels.json                    # gate only, no cloud
swift run detector-replay walk.mp4 --labels labels.json \
    --server http://localhost:8000 --token "$APP_TOKEN" --trip-type honeymoon   # with the backend
```

`labels.json` is `{"should_save_ms": [...], "tolerance_ms": 10000}`. It prints every hold, the final keep or release decision, the escalation rate (gate 6 wants at most 10 %) and whether each labeled moment was escalated and kept. Motion sensors aren't replayed, so `dwell` is 0. With `--server`, each request finishes before the next sample; start the backend with the trip budget raised (see `backend/tools/replay_eval.py`). Tune `Resources/detection_config.json`, not the code.
