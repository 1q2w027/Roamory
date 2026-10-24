# RoamoryKit

The phone-side Edit pipeline (TRD §9, Phase 2 of the video generation plan) as a local Swift package: Codable contract mirrors, the edit-spec validator, the fallback planner, the pre-pass, the AVFoundation renderer, the `/v1/plan` client and `EditCoordinator`. It has no app target of its own, so it builds and tests on macOS as well as iOS 26.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Edit/` | Models, `EditSpecValidator`, `FallbackPlanner`, `PrePass`, `Renderer` + `TitleOverlay`, `EditPlanner`, `EditCoordinator`, `RenderLabView` (debug) |
| `Sources/RoamoryKit/Cloud/` | `PlanClient` (`POST /v1/plan`, multipart) |
| `Sources/RoamoryKit/Config/` | `EditConfig` (`Resources/edit_config.json`) and bundled-file lookup |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `edit_config.json`, placeholder music beds, 2 s black end-card clips, RenderLab sample clips |
| `scripts/` | `sync-contracts.sh` (copy the presets after a contract change), `make-placeholder-assets.sh` (regenerate the media with ffmpeg) |

## Add it to the app

In Xcode: File > Add Package Dependencies… > Add Local… > `ios/RoamoryKit`, then add the `RoamoryKit` library to the app target. To try the renderer before capture exists, show `RenderLabView()` from a debug-only button. It renders the bundled samples, or any `.mp4` you put in the app's Documents folder. That folder shows in Files once the app's Info.plist has `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.

The cloud planner is used only when the app's Info.plist has `RoamoryAPIBaseURL` and `RoamoryAppToken`. Set them from an untracked `.xcconfig`, never commit the token. Without them, or with cloud analysis off, the fallback planner runs.

```swift
let coordinator = EditCoordinator(
    trip: trip, clips: clips, outputDirectory: tripFolder.appending(path: "video"),
    presets: try .bundled(), config: try .bundled(),
    service: PlanClient.fromBundle(config: try .bundled())
)
await coordinator.run()   // phase: planning -> rendering(progress) -> completed / error; run() again to retry
```

`ClipInfo(sidecar:moment:tripFolder:)` builds the input from a `clips/{id}.json` sidecar plus the Moment record's fields.

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac, including real renders of the sample clips.
- `xcodebuild test -scheme RoamoryKit -destination 'platform=iOS Simulator,name=iPhone 17'` runs on iOS.

Tests read `contracts/examples` straight from the repo. `ContractsTests` fails if the bundled presets drift from `contracts/style_presets.json`; run `scripts/sync-contracts.sh`.
