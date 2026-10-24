# RoamoryKit

Phone-side logic as a local Swift package, so it builds and tests on macOS as well as iOS 26: the onboarding catalog and the style presets with the capture orientation each one needs. The app (`ios/Roamory`) adds it as a local package.

| Folder | What |
|---|---|
| `Sources/RoamoryKit/Config/` | `StylePreset`/`StylePresets` (Codable mirror of `contracts/style_presets.json`), `CaptureOrientation` (16:9 styles record landscape, Reels portrait), `BundledResources` lookup |
| `Sources/RoamoryKit/Onboarding/` | `OnboardingCatalog` (continents, countries, cities, trip types from `onboarding_catalog.json`) and `GeoMath` for the destination globe |
| `Sources/RoamoryKit/Resources/` | `style_presets.json` (copy of `contracts/`), `onboarding_catalog.json`, `SampleClips/` (the style picker's looping samples) |
| `scripts/` | `sync-contracts.sh`: copy the presets after a contract change |

```swift
let presets = try StylePresets.bundled()
let orientation = CaptureOrientation(preset: presets[.reels])   // .portrait
let catalog = try OnboardingCatalog.bundled()
```

## Test

Needs a full Xcode (the command line tools ship no XCTest):

- `cd ios/RoamoryKit && swift test` runs on the Mac.
- `xcodebuild test -scheme RoamoryKit -destination 'platform=iOS Simulator,name=iPhone 17'` runs on iOS.

Tests read `contracts/` straight from the repo. `ContractsTests` fails if the bundled presets drift from `contracts/style_presets.json`; run `scripts/sync-contracts.sh`.
