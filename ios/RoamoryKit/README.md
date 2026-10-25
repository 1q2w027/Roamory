# RoamoryKit

Phone-side logic as a local Swift package, so it builds and tests on macOS as well as iOS 26: the onboarding catalog, the style presets with the capture orientation each one needs, and the on-phone AVFoundation video edit (the backup when Roamory Studio is not available). The app (`ios/Roamory`) adds it as a local package.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Config/` | `StylePreset`/`StylePresets` (Codable mirror of `contracts/style_presets.json`), `CaptureOrientation` (16:9 styles record landscape, Reels portrait), `EditConfig` (`edit_config.json`), `BundledResources` lookup |
| `Sources/RoamoryKit/Edit/` | `LocalPlanner` (evenly spaced cuts from the trip's clips at the preset's lengths), `EditSpec`, `EditTimeline`, `Renderer` + `TitleOverlay` (AVFoundation, restored from `main`) |
| `Sources/RoamoryKit/Onboarding/` | `OnboardingCatalog` (continents, countries, cities, trip types from `onboarding_catalog.json`) and `GeoMath` for the destination globe |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `onboarding_catalog.json`, `edit_config.json`, `Music/` (placeholder music beds), 2 s black end-card clips, `StylePreviews/` (the style picker's looping 9:16 previews, one per style, from Mixkit; sources in its `CREDITS.md`), `SampleClips/` (synthetic test patterns for the renderer tests) |
| `scripts/` | `sync-contracts.sh`: copy the presets after a contract change |

```swift
let presets = try StylePresets.bundled()
let orientation = CaptureOrientation(preset: presets[.reels])   // .portrait
let catalog = try OnboardingCatalog.bundled()

// On-phone video, no Mac or model:
let spec = LocalPlanner.plan(tripId: "t_1", style: .reels, preset: presets[.reels],
                             clips: [.init(id: "c_01", durationS: 48)], title: "Kyoto", subtitle: "October 2026",
                             endCardText: try EditConfig.bundled().endCardText)
let result = try await Renderer(config: try .bundled()).render(spec, clipURLs: ["c_01": clipURL], to: outputURL)
```

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac.
- `xcodebuild test -scheme RoamoryKit -destination 'platform=iOS Simulator,name=iPhone 17'` runs on iOS.

Tests read `contracts/` straight from the repo. `ContractsTests` fails if the bundled presets drift from `contracts/style_presets.json`; run `scripts/sync-contracts.sh`.
