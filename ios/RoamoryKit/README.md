# RoamoryKit

Phone-side logic as a local Swift package: the Edit pipeline (TRD §9, Phase 2 of the video generation plan) and Stage 1 moment detection (TRD §6). So far: Codable contract mirrors, the edit-spec validator and the fallback planner. It has no app target of its own, so it builds and tests on macOS as well as iOS 26.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Edit/` | Contract mirrors, `EditSpecValidator`, `FallbackPlanner` |
| `Sources/RoamoryKit/Signals/` | Stage 1 detection: frame signals, local score, escalation gate, `MomentDetector` |
| `Sources/RoamoryKit/Cloud/` | `POST /v1/evaluate` contract mirrors and `EvaluateClient` |
| `Sources/RoamoryKit/Config/` | `EditConfig` (`Resources/edit_config.json`), `DetectionConfig` (`Resources/detection_config.json`) and bundled-file lookup |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `edit_config.json` |
| `scripts/` | `sync-contracts.sh` (copy the presets after a contract change) |

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac.
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
