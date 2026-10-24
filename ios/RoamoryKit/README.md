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
