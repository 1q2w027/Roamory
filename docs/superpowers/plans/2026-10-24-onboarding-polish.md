# Onboarding Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five fixes to trip setup and recording: tapping a style card selects it, the destination defaults to the United States, the globe frames a continent instead of zooming in too far, the recording screen can go back to setup, and the key color is `#03fc73`.

**Architecture:** All work is in `ios/`. The onboarding code is on `origin/main` (PR #43, `ios/Roamory/Roamory/Onboarding/`), not on `ios/agent-mode`. Globe framing math and the default destination go in RoamoryKit, which has XCTest. The app target has no tests, so its changes are checked with `ios/Roamory/scripts/typecheck.sh` and on a phone.

**Tech Stack:** Swift 5 / SwiftUI, SceneKit (globe), AVFoundation, RoamoryKit Swift package (XCTest).

**Spec:** the user's five requests, quoted here:
1. "In the first section (selecting video style), when clicking on one of the cards, you should not need to also click 'use/keep x'. It should automatically select it and you just need to press 'continue'."
2. "In the second section, the default country is Japan. Make it the United States."
3. "In the second section, if you select Asia for example, the map scale is too big. Make the scale more reasonable."
4. "After you enter the video recording part, there is no way to go back to the initial setup. Make it so the user can go back."
5. "The key color is currently orange. Set it to HEX #03fc73."

## Global Constraints

- Branch: `git fetch origin && git switch -c ios/onboarding-polish origin/main`. Open one PR to `main`.
- Only edit files under `ios/`. Do not change `contracts/` or `docs/mockups/`.
- Commits and the PR carry no Claude attribution (CLAUDE.md overrides the default).
- Key color: `#03fc73` exactly.
- Default destination: continent `North America`, country `United States`, city `New York` (the catalog's two US cities are San Francisco and New York; a city is required to continue).
- Camera field of view stays 38°. World view distance stays 3.2 and the closest zoom stays 1.6.
- Leave the camera-style yellow (zoom dial, Review, TripFlowView `.tint(.yellow)`, TripleClickGuide) as it is: it is not the orange key color.
- Test commands: `cd ios/RoamoryKit && swift test` and `ios/Roamory/scripts/typecheck.sh` (expect `typecheck: ok`).

## Review Focus

1. **Back to setup, then a different style.** Reels records 9:16 and the others 16:9, fixed when the camera session starts. After going back and choosing another style, the new camera must start in the new orientation. The old `AVCaptureSession` has to stop before the new one starts, so `backToSetup()` awaits `camera.shutdown()` before calling `onBackToSetup`. Check on a phone (Task 5, Step 6).
2. **Back to setup while a moment clip is being written.** The kept clip must still be saved. `backToSetup()` uses `detection.endTrip()`, which waits for in-flight saves, and does not call `stop()` alone. Check on a phone (Task 5, Step 6).
3. **A country whose cities are far apart (the new default, San Francisco and New York, about 48° apart).** Both pins must be on screen. Pinned by `testFitShowsFarApartCities` (Task 3).
4. **A continent that crosses the antimeridian, or a country with one city.** Framing must not fly to the wrong side of the globe or divide by zero. Pinned by `testCenterAcrossAntimeridian` and `testFitSinglePointIsClosest` (Task 3).
5. **Existing installs.** `@AppStorage` keeps the last trip's answers, so a phone that already saved Japan keeps showing Japan. That is intended. The new default applies only when nothing has been saved yet. Mention this in the PR so testers delete and reinstall the app, or pick the United States once.

---

### Task 1: Key color `#03fc73`

**Files:**
- Modify: `ios/Roamory/Roamory/Onboarding/OnboardingStyle.swift:6-9,76`
- Modify: `ios/Roamory/Roamory/Onboarding/GlobeTexture.swift:8`
- Modify: `ios/Roamory/Roamory/Assets.xcassets/AccentColor.colorset/Contents.json`

**Interfaces:**
- Produces: `Theme.accent`, `Theme.accent2` and `Theme.accentInk` keep their names. Every existing use picks up the new colors.

- [ ] **Step 1: Set the theme colors in `OnboardingStyle.swift`**

`accent = Color(hex: "#03fc73")`, `accent2 = Color(hex: "#8dffbe")` (the lighter end of the gradient, eyebrow text and pin heads), `accentInk = Color(hex: "#02200f")` (dark text on the green). Change the `AccentButton` doc comment from "orange" to "green".

- [ ] **Step 2: Set the globe's continent highlight in `GlobeTexture.swift`**

Change `highlight` to `0x03, 0xfc, 0x73`. The land is a muted `#3d6b52`, so the lit continent still stands out.

- [ ] **Step 3: Set the asset catalog's AccentColor**

Add `"color": {"color-space": "srgb", "components": {"red": "0x03", "green": "0xFC", "blue": "0x73", "alpha": "1.000"}}` to the universal entry, so system tints (alerts, toggles, the settings sheet) match.

- [ ] **Step 4: Type-check**

Run: `ios/Roamory/scripts/typecheck.sh`. Expected: `typecheck: ok`.

- [ ] **Step 5: Commit**

```bash
git add ios/Roamory/Roamory/Onboarding/OnboardingStyle.swift ios/Roamory/Roamory/Onboarding/GlobeTexture.swift ios/Roamory/Roamory/Assets.xcassets/AccentColor.colorset/Contents.json
git commit -m "iOS app: key color #03fc73"
```

---

### Task 2: Default destination is the United States

**Files:**
- Modify: `ios/RoamoryKit/Sources/RoamoryKit/Onboarding/OnboardingCatalog.swift`
- Modify: `ios/Roamory/Roamory/Onboarding/OnboardingView.swift:10-12`
- Modify: `ios/Roamory/Roamory/DetectionSettingsView.swift:21-23,53-55`
- Test: `ios/RoamoryKit/Tests/RoamoryKitTests/OnboardingCatalogTests.swift`

**Interfaces:**
- Produces: `OnboardingCatalog.defaultContinent`, `.defaultCountry` and `.defaultCity` (`public static let ... : String`), equal to `"North America"`, `"United States"` and `"New York"`. Every place that defaults a destination uses these, so there is one source.

- [ ] **Step 1: Write the failing test**

```swift
func testDefaultDestinationIsInTheCatalog() {
    XCTAssertEqual(OnboardingCatalog.defaultCountry, "United States")
    let continent = catalog.continents.first { $0.name == OnboardingCatalog.defaultContinent }
    let country = continent?.countries.first { $0.name == OnboardingCatalog.defaultCountry }
    XCTAssertNotNil(country?.cities.first { $0.name == OnboardingCatalog.defaultCity })
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `cd ios/RoamoryKit && swift test --filter OnboardingCatalogTests`. Expected: a compile failure, because `defaultCountry` is not defined.

- [ ] **Step 3: Add the three constants to `OnboardingCatalog`, then use them in the app**

Replace the literals `"Asia"`, `"Japan"` and `"Kyoto"` with the constants in `OnboardingView`'s `@AppStorage` defaults, in `DetectionSettings`'s stored defaults, and in `DetectionSettingsView`'s `@AppStorage` defaults. Leave `RenderLab.swift`, `DetectorReplay` and the test fixtures alone: they are fixed sample data, not user defaults.

- [ ] **Step 4: Run the tests and type-check**

Run: `cd ios/RoamoryKit && swift test`, then `ios/Roamory/scripts/typecheck.sh`. Expected: all tests pass and `typecheck: ok`.

- [ ] **Step 5: Commit**

```bash
git add ios/RoamoryKit/Sources/RoamoryKit/Onboarding/OnboardingCatalog.swift ios/RoamoryKit/Tests/RoamoryKitTests/OnboardingCatalogTests.swift ios/Roamory/Roamory/Onboarding/OnboardingView.swift ios/Roamory/Roamory/DetectionSettingsView.swift
git commit -m "iOS: default destination New York, United States"
```

---

### Task 3: Globe frames the whole continent or country

At the moment the continent zoom is a fixed camera distance of 2.2. That shows about 47° of arc, and Asia reaches 67° from its center, so most of it is off screen. The fix is to compute the distance from what has to be visible.

**Files:**
- Modify: `ios/RoamoryKit/Sources/RoamoryKit/Onboarding/GeoMath.swift`
- Modify: `ios/RoamoryKit/Sources/RoamoryKit/Onboarding/OnboardingCatalog.swift` (`Country.center`)
- Modify: `ios/Roamory/Roamory/Onboarding/GlobeView.swift:5-16,26,54,83,131-144,263`
- Modify: `ios/Roamory/Roamory/Onboarding/DestinationStep.swift:41-50`
- Test: `ios/RoamoryKit/Tests/RoamoryKitTests/OnboardingCatalogTests.swift`

**Interfaces:**
- Produces, in `GeoMath`:
  - `public static func angle(_ a: GeoPoint, _ b: GeoPoint) -> Double`: the great-circle angle in radians, computed from `unitVector`s (`acos` of the clamped dot product), so it is safe across the antimeridian.
  - `public static func center(of points: [GeoPoint]) -> GeoPoint`: `geoPoint` of the sum of the points' `unitVector`s. Precondition: `points` is not empty.
  - `public static func cameraDistance(fitting points: [GeoPoint], around center: GeoPoint, fieldOfView: Double, fill: Double, range: ClosedRange<Double>) -> Double`. `fieldOfView` is in degrees. `fill` is the fraction of the half field of view that the farthest point may reach.
- Produces: `Country.center: GeoPoint` = `GeoMath.center(of: cities.map(\.location))`.
- Produces, in `GlobeView`: `static let worldDistance = 3.2`, `static let closestDistance = 1.6`, `static let fieldOfView = 38.0`. `var distance: Double` replaces `var zoom: GlobeZoom`, and the `GlobeZoom` enum is deleted.

- [ ] **Step 1: Write the failing tests**

```swift
private func fit(_ points: [GeoPoint], around c: GeoPoint) -> Double {
    GeoMath.cameraDistance(fitting: points, around: c, fieldOfView: 38, fill: 0.9, range: 1.6...3.2)
}

func testFitAsiaZoomsOutToWorldView() {
    let asia = catalog.continents.first { $0.id == "asia" }!
    XCTAssertEqual(fit(asia.outlines.flatMap { $0 }, around: asia.center), 3.2, accuracy: 1e-9)
}

func testFitEuropeIsBetweenOldZoomAndWorld() {
    let europe = catalog.continents.first { $0.id == "europe" }!
    let d = fit(europe.outlines.flatMap { $0 }, around: europe.center)
    XCTAssertGreaterThan(d, 2.2)
    XCTAssertLessThan(d, 3.2)
    // Unclamped, so the farthest outline point sits exactly at fill × half the field of view.
    let theta = europe.outlines.flatMap { $0 }.map { GeoMath.angle(europe.center, $0) }.max()!
    XCTAssertEqual(atan(sin(theta) / (d - cos(theta))), 0.9 * 19 * .pi / 180, accuracy: 1e-9)
}

func testFitShowsFarApartCities() {
    let us = catalog.continents.flatMap(\.countries).first { $0.name == "United States" }!
    let sf = us.cities.first { $0.name == "San Francisco" }!.location
    XCTAssertGreaterThan(fit(us.cities.map(\.location), around: sf), 2.5)
}

func testFitSinglePointIsClosest() {
    let p = GeoPoint(lat: -33.87, lon: 151.21)
    XCTAssertEqual(fit([p], around: p), 1.6)
}

func testCenterAcrossAntimeridian() {
    let c = GeoMath.center(of: [GeoPoint(lat: 0, lon: 170), GeoPoint(lat: 0, lon: -170)])
    XCTAssertEqual(abs(c.lon), 180, accuracy: 1e-9)
    XCTAssertEqual(c.lat, 0, accuracy: 1e-9)
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd ios/RoamoryKit && swift test --filter OnboardingCatalogTests`. Expected: a compile failure, because `cameraDistance` is not defined.

- [ ] **Step 3: Implement `angle`, `center` and `cameraDistance` in `GeoMath`, and `Country.center`**

`cameraDistance` works as follows. Let θ be the largest `angle(center, p)` (0 when `points` is empty), and let α = `fill × fieldOfView / 2` in radians. A point θ from the sub-camera point, seen from distance d on the axis, appears at `atan(sin θ / (d − cos θ))`. Solving for that angle equal to α gives `d = cos θ + sin θ / tan α`. Clamp the result to `range`. A cap too wide to fit, like Asia, comes out above 3.2 and clamps to world view.

- [ ] **Step 4: Run the tests**

Run: `cd ios/RoamoryKit && swift test`. Expected: all tests pass.

- [ ] **Step 5: Drive the globe by distance**

`GlobeView`: delete `GlobeZoom` and add the three constants. Use `fieldOfView` for `camera.camera?.fieldOfView`. Use `worldDistance` for the initial `distance` and in the drag-speed formula at line 263. The focus key becomes `"\(lat),\(lon),\(distance)"`, or `"none,\(distance)"` with no focus, and `target.distance` is `globeView.distance`.

`DestinationStep`, inside `globe(side:)`:
- focus: `currentCity?.location ?? currentCountry?.center ?? currentContinent?.center`, nil until `revealed`, as now.
- distance:
  - `GlobeView.worldDistance` when not `revealed` or with no continent.
  - With a country: `cameraDistance(fitting: country.cities.map(\.location), around: focus, ...)`.
  - Otherwise: `cameraDistance(fitting: continent.outlines.flatMap { $0 }, around: continent.center, ...)`.
  - Both calls use `fieldOfView: GlobeView.fieldOfView, fill: 0.9, range: GlobeView.closestDistance...GlobeView.worldDistance`.

- [ ] **Step 6: Type-check, then look on a phone**

Run: `ios/Roamory/scripts/typecheck.sh`. Expected: `typecheck: ok`.

On a phone, with launch argument `-onboardingStep 1`:
- Asia shows the whole continent lit, not a close-up of China.
- Europe shows the whole continent and is closer than world view.
- United States shows both San Francisco and New York pins.
- Japan still zooms in close.

- [ ] **Step 7: Commit**

```bash
git add ios/RoamoryKit ios/Roamory/Roamory/Onboarding/GlobeView.swift ios/Roamory/Roamory/Onboarding/DestinationStep.swift
git commit -m "iOS app: globe frames the whole continent or country"
```

---

### Task 4: Tapping a style card selects it

**Files:**
- Modify: `ios/Roamory/Roamory/Onboarding/StylePickerStep.swift:28,74-79,117-134,172`

**Interfaces:**
- Consumes: `OnboardingView`'s `Continue` button, below the step, which stays visible while a card is expanded. No interface change.

- [ ] **Step 1: Select on tap and remove the Use/Keep button**

- In `expand(_:)`, set `style = s.rawValue` before the animation.
- In `expandedCard`, delete the `AccentButton` overlay.
- Delete `choose(_:)`.
- In `StyleTile`, change `.padding(.bottom, large ? 84 : 0)` to `.padding(.bottom, 0)` (or drop it), because the button no longer takes that space.
- Closing the preview (✕, tap, or drag down) keeps the selection.
- Change the footnote to `"Tap one to choose it and watch it with sound."`

- [ ] **Step 2: Type-check, then try it on a phone**

Run: `ios/Roamory/scripts/typecheck.sh`. Expected: `typecheck: ok`.

On a phone: tap Vlog, and it opens with sound and the ring moves to Vlog. Press Continue without closing the preview, and step 2 opens. Go back and Vlog is still ringed.

- [ ] **Step 3: Commit**

```bash
git add ios/Roamory/Roamory/Onboarding/StylePickerStep.swift
git commit -m "iOS app: tapping a style card selects it"
```

---

### Task 5: Back to setup from recording

**Files:**
- Modify: `ios/Roamory/Roamory/RootView.swift:10-15`
- Modify: `ios/Roamory/Roamory/ContentView.swift` (the top-leading overlay at line 80, a new `confirmationDialog`, and a new `backToSetup()`)
- Modify: `ios/Roamory/Roamory/CameraService.swift` (new `shutdown()`)
- Modify: `ios/Roamory/Roamory/HeadphoneButton.swift` (new `stop()`)

**Interfaces:**
- Produces:
  - `ContentView.init(onBackToSetup: @escaping () -> Void)`, a stored `let onBackToSetup: () -> Void`. Update any `#Preview` that builds `ContentView()`.
  - `CameraService.shutdown() async`: calls `stopSaving()` if `isSaving`, then `session.stopRunning()` on `sessionQueue` (awaited with a continuation, like `prepare`), then sets `isReady = false` and `UIApplication.shared.isIdleTimerDisabled = false`.
  - `HeadphoneButton.stop()`: removes `routeObserver` (and sets it to nil) and calls `stopListening()`.

- [ ] **Step 1: Add `HeadphoneButton.stop()` and `CameraService.shutdown()`** as specified above.

- [ ] **Step 2: Add `backToSetup()` and the confirmation in `ContentView`**

New state: `@State private var confirmBack = false` and `@State private var isLeaving = false`.

`backToSetup()` sets `isLeaving = true`. Then, in a `Task`, it does these in order:
1. `_ = await detection.endTrip()`: this ends the trip without a video, waits for in-flight clip saves, and returns nil when no trip is running.
2. `headphones.stop()`
3. `await camera.shutdown()`
4. `onBackToSetup()`

Dialog: `.confirmationDialog("Back to trip setup?", isPresented: $confirmBack, titleVisibility: .visible)`.
- A destructive button `"Back to setup"` that calls `backToSetup()`.
- A cancel button.
- Message: `"Recording stops and this trip ends without a video. Moments already kept stay on the phone."`

Open the dialog only while the curtain is awake or detection is not running, which is when the top-left overlay is visible.

- [ ] **Step 3: Add the button**

In the top-leading overlay, put an `HStack(spacing: 8)` holding a new button in front of `detectionSettingsButton`:
- Image `chevron.left`, 44×44, white on `.black.opacity(0.5)` in a `Circle()`, matching `detectionSettingsButton`.
- `accessibilityLabel("Back to trip setup")`.
- Action `confirmBack = true`.
- Disabled while `isEnding || isLeaving`.

Move `.padding(.leading, 16)` from `detectionSettingsButton` onto the `HStack`. Like now, the settings button is disabled while `isEnding`.

- [ ] **Step 4: Wire `RootView`**

`ContentView(onBackToSetup: { withAnimation(.easeInOut(duration: 0.6)) { setupDone = false } })`. Onboarding reopens at step 1 with the saved answers filled in.

- [ ] **Step 5: Type-check and build**

Run: `ios/Roamory/scripts/typecheck.sh`. Expected: `typecheck: ok`.

Then run `cd ios/Roamory && xcodebuild build -scheme Roamory -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`. Expected: `** BUILD SUCCEEDED **`. If this Mac's Xcode cannot open the project, say so and rely on the type-check.

- [ ] **Step 6: Check on a phone**

1. Start recording in Cinematic and keep a moment with a volume key.
2. Within about 2 s, wake the curtain, tap ←, and confirm. Setup opens. The kept clip is in Files > On My iPhone > Roamory > trips.
3. Choose Reels and Start. The preview and recording are 9:16 upright.
4. Tap ← and then Cancel. Recording carries on.

- [ ] **Step 7: Commit**

```bash
git add ios/Roamory/Roamory/RootView.swift ios/Roamory/Roamory/ContentView.swift ios/Roamory/Roamory/CameraService.swift ios/Roamory/Roamory/HeadphoneButton.swift
git commit -m "iOS app: back to trip setup from recording"
```

---

### Finish

- [ ] Run `cd ios/RoamoryKit && swift test` and `ios/Roamory/scripts/typecheck.sh` once more. Both pass.
- [ ] Push `ios/onboarding-polish` and open a PR to `main` that lists the five changes and the existing-installs note from Review Focus 5. Daniel owns the screens: ask them to review.
