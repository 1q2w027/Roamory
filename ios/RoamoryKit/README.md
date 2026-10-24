# RoamoryKit

Phone-side logic as a local Swift package: the Edit side (TRD §9) and Stage 1 moment detection (TRD §6). The Edit side has Codable contract mirrors, the pre-pass, the `/v1/agent` client and `EditCoordinator`; the video itself is made by the agent in the render service. It has no app target of its own, so it builds and tests on macOS as well as iOS 26.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Edit/` | Models, `PrePass`, `ClipTrimmer` (whole-clip re-encode for upload), `RenderResult`, `EditCoordinator` |
| `Sources/RoamoryKit/Signals/` | Stage 1 detection: frame signals, local score, escalation gate, `MomentDetector` |
| `Sources/RoamoryKit/Cloud/` | `AgentRenderClient` (`/v1/agent`) on `RenderServiceHTTP`, `POST /v1/evaluate` contract mirrors and `EvaluateClient` |
| `Sources/RoamoryKit/Trip/` | `TripPipeline`: an ended trip's clips to a highlight video |
| `Sources/RoamoryKit/Config/` | `EditConfig` (`Resources/edit_config.json`), `DetectionConfig` (`Resources/detection_config.json`) and bundled-file lookup |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `edit_config.json`, placeholder music beds (synced to the render service), sample clips (onboarding style previews and tests) |
| `scripts/` | `sync-contracts.sh` (copy the presets after a contract change), `make-placeholder-assets.sh` (regenerate the media with ffmpeg) |

## Add it to the app

In Xcode: File > Add Package Dependencies… > Add Local… > `ios/RoamoryKit`, then add the `RoamoryKit` library to the app target.

The app's Info.plist needs `RoamoryRenderBaseURL` and `RoamoryAppToken` for the render service (`render/`). Set them from an untracked `.xcconfig`, never commit the token. Without them every edit fails with an error.

```swift
let coordinator = EditCoordinator(
    trip: trip, clips: clips, outputDirectory: tripFolder.appending(path: "video"),
    presets: try .bundled(), config: try .bundled(),
    agent: AgentRenderClient.fromBundle(config: try .bundled())
)
await coordinator.run()   // phase: planning -> rendering(progress) -> completed / error; run() again to retry
```

After the pre-pass (dedupe, best window per clip), `AgentRenderClient` re-encodes every candidate clip whole at `agent_upload_preset`, uploads them to `/v1/agent` (TRD §9), polls, fetches the result (title, moments, `total_s`) and then the MP4, and checks its duration against `total_s`. Review's moments come from the result. On any error, or after `agent_timeout_s`, the coordinator ends in `.error(.rendering, …)` and Processing offers Retry.

`ClipInfo(sidecar:moment:tripFolder:)` builds the input from a `clips/{id}.json` sidecar plus the Moment record's fields.

### From an ended trip

At End trip the app (`ios/Roamory`) reads the trip's saved clips back with `TripFolder.loadClips(in:)` and makes the video with `TripPipeline`, which runs `EditCoordinator` into `{folder}/video/`:

```swift
let pipeline = TripPipeline(trip: trip, folder: folder, clips: TripFolder.loadClips(in: folder))
await pipeline.start()
// phase: editing (pipeline.coordinator has planning/rendering/completed/error) or failed
await pipeline.retry()                    // after an error
await pipeline.rerender(style: .reels)    // same clips, another style
```

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac, including real re-encodes of the sample clips.
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
