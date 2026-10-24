# RoamoryKit

The phone-side Edit pipeline (TRD §9, Phase 2 of the video generation plan) as a local Swift package. So far: Codable contract mirrors, the edit-spec validator and the fallback planner, the AVFoundation renderer and the pre-pass. It has no app target of its own, so it builds and tests on macOS as well as iOS 26.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Edit/` | Contract mirrors, `EditSpecValidator`, `FallbackPlanner`, `Renderer` + `TitleOverlay`, `RenderLab` helpers, `PrePass` |
| `Sources/RoamoryKit/Config/` | `EditConfig` (`Resources/edit_config.json`) and bundled-file lookup |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `edit_config.json`, placeholder music beds, 2 s black end-card clips, RenderLab sample clips |
| `scripts/` | `sync-contracts.sh` (copy the presets after a contract change), `make-placeholder-assets.sh` (regenerate the media with ffmpeg) |

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac, including real renders of the sample clips.
- `xcodebuild test -scheme RoamoryKit -destination 'platform=iOS Simulator,name=iPhone 17'` runs on iOS.

Tests read `contracts/examples` straight from the repo. `ContractsTests` fails if the bundled presets drift from `contracts/style_presets.json`; run `scripts/sync-contracts.sh`.
