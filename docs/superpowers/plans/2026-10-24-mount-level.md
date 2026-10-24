# Mount Level and Landscape Recording Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 2-axis bubble level with haptic guidance over the camera preview when the recording screen opens, and a landscape layout of the recording screen for 16:9 styles.

**Architecture:** All leveling logic is pure code in RoamoryKit with XCTest: gravity → pose, the settle detector, the degree ticker and a `LevelGuide` that turns motion samples into haptic events. The app adds a CoreMotion monitor, a Core Haptics player and a SwiftUI overlay in `Recording/`. Landscape works like this: the iPhone build allows landscape, an app delegate holds an orientation lock, and the recording screen locks it to the side the camera records. `CameraService` gains one read-only published value with that side.

**Tech Stack:** Swift 5 / SwiftUI (iOS 26), CoreMotion, Core Haptics, AVFoundation, RoamoryKit Swift package (XCTest).

**Spec:** `docs/superpowers/specs/2026-10-24-mount-level-design.md`

## Global Constraints

- Branch `ios/mount-level` already exists (from `origin/dev`, spec committed). Small PR to `dev`, never to `main`.
- Edit only `ios/`, plus one line in `CLAUDE.md` (Task 5). Do not touch `contracts/`.
- No Claude attribution in commits or PRs (no `Co-Authored-By`, no "Generated with" line). English only in anything pushed.
- `ios/Roamory/Roamory.xcodeproj/project.pbxproj` has uncommitted local signing changes (`DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`). Never `git add` that file whole. Task 4 Step 5 stages only the orientation line.
- Capture code: the only change to `CameraService` is `captureRotationAngle` (Task 3). Nothing else in `Capture/`.
- Thresholds are config: `ios/RoamoryKit/Sources/RoamoryKit/Resources/level_config.json` (Task 1) holds every tuning number below; code reads them from `LevelConfig`.
- Level means both axes within ±1°, the phone still (rotation rate ≤ 0.15 rad/s), held for 1 s. Leaving level means either axis beyond 2°.
- Level color is `Theme.accent` (`#03fc73`).
- On-screen copy, exactly: `Turn the phone sideways`, `Hold the phone upright`, `Turn the phone the other way round`, `Tilt %.0f° · Aim %.0f°`, `Tap to close`. Level button accessibility label: `Level the phone`.
- Commit subjects follow the log: `iOS: …` for RoamoryKit, `iOS app: …` for the app.
- Checks: `cd ios/RoamoryKit && swift test` (all pass); `ios/Roamory/scripts/typecheck.sh` prints `typecheck: ok`. Haptics, motion and layout are checked on an iPhone by the user (Task 5); the Simulator has neither camera nor motion.

## Review Focus

1. **Haptics while the buffer records.** iOS mutes haptics while the audio session records. Expected: ticks and the success double tap are felt with the camera running. `LevelHaptics.start()` sets `setAllowHapticsAndSystemSoundsDuringRecording(true)` and the engine uses `AVAudioSession.sharedInstance()` (Task 3). Phone check in Task 5.
2. **Axis signs on a real phone.** Expected: the bubble and arrows move the right way in portrait and on both landscape sides, and a 16:9 trip's interface comes up upright with the column on the user's right. The math is pinned by `testRightSideLowGivesPositiveTilt`, `testCameraAimedUpGivesPositiveAim`, `testLandscapeRightSideLowOnEachSide` (Task 1) and `testInterfaceSideForCaptureAngle` (Task 4). The device conventions (capture angle 0 = top of phone to the left) are checked in Task 5.
3. **Passing through level while clipping the phone in.** Expected: no success until the phone is still for 1 s. Pinned by `testMovingThroughLevelDoesNotCount` (Task 2).
4. **Mount wobble and hand tremor.** Expected: no tick flood, no repeated success. Pinned by `testNoiseAroundADegreeDoesNotTick`, `testTicksAreRateLimited`, `testSuccessOnlyOnce` and `testSmoothingDampsASpike` (Task 2).
5. **Phone lying flat before it is mounted.** Expected: the bubble stays up with a large aim reading and the prompt does not flicker. Pinned by `testFlatPhoneStaysAligned` (Task 1).

Known limitation (not fixed): a Reels trip started with the phone upside down records at 270°. The iPhone interface has no upside-down portrait, so the arrows read mirrored. Mention it in the PR.

---

### Task 1: Level pose math and config (RoamoryKit)

**Files:**
- Create: `ios/RoamoryKit/Sources/RoamoryKit/Resources/level_config.json`
- Create: `ios/RoamoryKit/Sources/RoamoryKit/Config/LevelConfig.swift`
- Create: `ios/RoamoryKit/Sources/RoamoryKit/Level/LevelPose.swift`
- Test: `ios/RoamoryKit/Tests/RoamoryKitTests/LevelPoseTests.swift`

**Interfaces:**
- Produces:
  - `public struct LevelConfig: Codable, Sendable, Equatable` with `public var` Doubles `toleranceDeg, leaveDeg, settleS, stillRadS, flatGravity, tickStepDeg, tickMinIntervalS, tickFarDeg, tickMinIntensity, smoothing, updateHz, bubbleRangeDeg, fadeDelayS`, plus `public static func bundled() throws -> LevelConfig`.
  - `public enum LevelPose: Equatable, Sendable { case aligned(tilt: Double, aim: Double); case turnSideways; case holdUpright; case turnOver }`. Angles are in degrees.
  - `public enum LevelMath { public static func pose(gravity: SIMD3<Double>, captureAngle: Double, flatGravity: Double) -> LevelPose }`.

- [ ] **Step 1: Write the failing tests** in `LevelPoseTests.swift`

```swift
import XCTest
@testable import RoamoryKit

private func rad(_ d: Double) -> Double { d * .pi / 180 }

private func assertAligned(_ pose: LevelPose, tilt: Double, aim: Double,
                           file: StaticString = #filePath, line: UInt = #line) {
    guard case let .aligned(t, a) = pose else { return XCTFail("expected aligned, got \(pose)", file: file, line: line) }
    XCTAssertEqual(t, tilt, accuracy: 0.01, file: file, line: line)
    XCTAssertEqual(a, aim, accuracy: 0.01, file: file, line: line)
}

final class LevelPoseTests: XCTestCase {
    private func pose(_ x: Double, _ y: Double, _ z: Double, _ angle: Double) -> LevelPose {
        LevelMath.pose(gravity: SIMD3(x, y, z), captureAngle: angle, flatGravity: 0.35)
    }

    func testUprightPortraitIsLevel() { assertAligned(pose(0, -1, 0, 90), tilt: 0, aim: 0) }

    func testRightSideLowGivesPositiveTilt() {
        assertAligned(pose(sin(rad(10)), -cos(rad(10)), 0, 90), tilt: 10, aim: 0)
    }

    func testCameraAimedUpGivesPositiveAim() {
        assertAligned(pose(0, -cos(rad(5)), sin(rad(5)), 90), tilt: 0, aim: 5)
    }

    func testLandscapeRightSideLowOnEachSide() {
        assertAligned(pose(1, 0, 0, 0), tilt: 0, aim: 0)                          // top of the phone to the left
        assertAligned(pose(-1, 0, 0, 180), tilt: 0, aim: 0)                       // top to the right
        assertAligned(pose(cos(rad(10)), -sin(rad(10)), 0, 0), tilt: 10, aim: 0)
        assertAligned(pose(-cos(rad(10)), sin(rad(10)), 0, 180), tilt: 10, aim: 0)
    }

    func testWrongOrientationPrompts() {
        XCTAssertEqual(pose(0, -1, 0, 0), .turnSideways)     // 16:9 trip, phone upright
        XCTAssertEqual(pose(0, -1, 0, 180), .turnSideways)
        XCTAssertEqual(pose(1, 0, 0, 90), .holdUpright)      // Reels trip, phone sideways
    }

    func testOtherSideUpPromptsTurnOver() {
        XCTAssertEqual(pose(-1, 0, 0, 0), .turnOver)
        XCTAssertEqual(pose(0, 1, 0, 90), .turnOver)
    }

    func testFlatPhoneStaysAligned() {
        assertAligned(pose(0, 0, -1, 90), tilt: 0, aim: -90)
        guard case .aligned(let tilt, _) = pose(0.1, 0.1, -0.99, 0) else { return XCTFail("expected aligned") }
        XCTAssertEqual(tilt, 0)
    }

    func testBundledConfigMatchesSpec() throws {
        let config = try LevelConfig.bundled()
        XCTAssertEqual(config.toleranceDeg, 1)
        XCTAssertEqual(config.leaveDeg, 2)
        XCTAssertEqual(config.settleS, 1)
        XCTAssertEqual(config.stillRadS, 0.15)
    }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `cd ios/RoamoryKit && swift test --filter LevelPoseTests`
Expected: build error, `cannot find 'LevelMath' in scope`.

- [ ] **Step 3: Add `level_config.json`** with snake_case keys and these values: `tolerance_deg` 1.0, `leave_deg` 2.0, `settle_s` 1.0, `still_rad_s` 0.15, `flat_gravity` 0.35, `tick_step_deg` 1.0, `tick_min_interval_s` 0.06, `tick_far_deg` 10, `tick_min_intensity` 0.3, `smoothing` 0.2, `update_hz` 50, `bubble_range_deg` 10, `fade_delay_s` 1.0.

- [ ] **Step 4: Implement `LevelConfig`** like `EditConfig`: `CodingKeys` mapping to the JSON keys, a doc comment per field, and `bundled()` via `BundledResources.decode(LevelConfig.self, named: "level_config")`.

- [ ] **Step 5: Implement `LevelMath.pose`** in `Level/LevelPose.swift`. Doc comments say that gravity is CoreMotion device coordinates (x to the right of the screen, y to the top, z out of the screen), that `captureAngle` is the horizon-level capture rotation in degrees (90 portrait, 0 = top of the phone to the left), that tilt > 0 means the frame's right side is low, and that aim > 0 means the camera points up.

```
g = normalize(gravity)                        // zero vector → .aligned(0, 0)
θ = captureAngle in radians
up    = (-cos θ,  sin θ, 0)                   // the recorded frame's up, in device coordinates
right = ( sin θ, -cos θ, 0)
down  = -(g · up);  side = g · right
aim   = asin(clamp(g.z, -1, 1)) in degrees
if hypot(down, side) < flatGravity: return .aligned(tilt: 0, aim: aim)
φ = atan2(side, down) in degrees
|φ| <= 45  → .aligned(tilt: φ, aim: aim)
|φ| >= 135 → .turnOver
otherwise  → captureAngle is landscape (cos θ dominates, i.e. |cos θ| > |sin θ|) ? .turnSideways : .holdUpright
```

- [ ] **Step 6: Run the tests and see them pass**

Run: `cd ios/RoamoryKit && swift test`
Expected: all tests pass, including the 8 in `LevelPoseTests`.

- [ ] **Step 7: Commit**

```bash
git add ios/RoamoryKit/Sources/RoamoryKit/Resources/level_config.json ios/RoamoryKit/Sources/RoamoryKit/Config/LevelConfig.swift ios/RoamoryKit/Sources/RoamoryKit/Level/LevelPose.swift ios/RoamoryKit/Tests/RoamoryKitTests/LevelPoseTests.swift
git commit -m "iOS: level pose from gravity and the capture side, with tuning in level_config.json"
```

---

### Task 2: Level detector, degree ticks and `LevelGuide` (RoamoryKit)

**Files:**
- Create: `ios/RoamoryKit/Sources/RoamoryKit/Level/LevelGuide.swift` (holds `LevelDetector`, `DegreeTicker`, `LevelGuide`)
- Test: `ios/RoamoryKit/Tests/RoamoryKitTests/LevelGuideTests.swift`

**Interfaces:**
- Consumes: `LevelConfig`, `LevelPose`, `LevelMath.pose` (Task 1).
- Produces:
  - `public enum LevelEvent: Equatable, Sendable { case reached, left }`
  - `public struct LevelDetector: Sendable`: `public init(config: LevelConfig)`, `public private(set) var isLevel: Bool`, `public mutating func update(tilt: Double, aim: Double, rotationRate: Double, at time: TimeInterval) -> LevelEvent?`, `public mutating func lost() -> LevelEvent?`
  - `public struct DegreeTicker: Sendable`: `public init(config: LevelConfig)`, `public mutating func update(tilt: Double, aim: Double, at time: TimeInterval) -> Double?` (a tick's intensity in 0...1), `public mutating func reset()`
  - `public enum LevelHaptic: Equatable, Sendable { case tick(intensity: Double), success, warning }`
  - `public struct LevelGuide: Sendable`: `public init(captureAngle: Double, config: LevelConfig)`, `public private(set) var pose: LevelPose?`, `public var isLevel: Bool`, `public mutating func update(gravity: SIMD3<Double>, rotationRate: SIMD3<Double>, at time: TimeInterval) -> LevelHaptic?`

Behavior the tests pin:
- **Detector.** A sample is *inside* when `max(|tilt|, |aim|) <= toleranceDeg` and `rotationRate <= stillRadS`. The first inside sample starts the count, and any sample that is not inside clears it. `.reached` fires once, when `time - start >= settleS`, and sets `isLevel`. While `isLevel`, a sample with `max(|tilt|, |aim|) > leaveDeg` returns `.left`, clears `isLevel` and the count. `lost()` returns `.left` only if `isLevel`, then clears both.
- **Ticker.** The first sample sets each axis's anchor to its value rounded to `tickStepDeg` and does not tick. A sample ticks when either axis is `>= tickStepDeg` away from its anchor and the last tick was at least `tickMinIntervalS` ago. On a tick, both anchors are re-rounded to the current values. A rate-limited sample leaves the anchors as they are. Intensity is `tickMinIntensity + (1 - tickMinIntensity) * max(0, 1 - max(|tilt|, |aim|) / tickFarDeg)`, using the values after the move.
- **Guide.** Gravity is low-pass filtered: the first sample is taken as is, then `g += smoothing * (new - g)`. Then `pose = LevelMath.pose(...)`.
  - When the pose is `.aligned`: `.reached` → `.success` and `.left` → `.warning`, and these win over a tick in the same sample. Otherwise a ticker intensity → `.tick`.
  - When the pose is not aligned: `detector.lost()` → `.warning`, and the ticker is reset.
  - The rotation rate passed to the detector is the vector's length.

- [ ] **Step 1: Write the failing tests** in `LevelGuideTests.swift`. Build configs from the bundled file: `var c = try LevelConfig.bundled()` and set `c.smoothing = 1` where a test needs raw samples.

```swift
final class LevelGuideTests: XCTestCase {
    private var config: LevelConfig!
    override func setUpWithError() throws { config = try LevelConfig.bundled(); config.smoothing = 1 }

    func testLevelNeedsOneStillSecond() {
        var d = LevelDetector(config: config)
        XCTAssertNil(d.update(tilt: 0.5, aim: 0.5, rotationRate: 0, at: 0))
        XCTAssertNil(d.update(tilt: 0.5, aim: 0.5, rotationRate: 0, at: 0.99))
        XCTAssertEqual(d.update(tilt: 0.5, aim: 0.5, rotationRate: 0, at: 1.0), .reached)
        XCTAssertNil(d.update(tilt: 0.5, aim: 0.5, rotationRate: 0, at: 1.5))
        XCTAssertTrue(d.isLevel)
    }

    func testMovingThroughLevelDoesNotCount() {
        var d = LevelDetector(config: config)
        for i in 0...100 { XCTAssertNil(d.update(tilt: 0, aim: 0, rotationRate: 0.5, at: Double(i) * 0.02)) }
        XCTAssertFalse(d.isLevel)
    }

    func testLeavingToleranceRestartsTheCount() {
        var d = LevelDetector(config: config)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0)
        _ = d.update(tilt: 3, aim: 0, rotationRate: 0, at: 0.6)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0.7)
        XCTAssertNil(d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1.6))
        XCTAssertEqual(d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1.75), .reached)
    }

    func testLeftNeedsMoreThanTheLeaveThreshold() {
        var d = LevelDetector(config: config)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1)
        XCTAssertNil(d.update(tilt: 1.5, aim: 0, rotationRate: 0, at: 1.1))
        XCTAssertEqual(d.update(tilt: 0, aim: -2.5, rotationRate: 0, at: 1.2), .left)
        XCTAssertNil(d.update(tilt: 0, aim: -2.5, rotationRate: 0, at: 1.3))
    }

    func testLostWarnsOnlyWhenLevel() {
        var d = LevelDetector(config: config)
        XCTAssertNil(d.lost())
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 0)
        _ = d.update(tilt: 0, aim: 0, rotationRate: 0, at: 1)
        XCTAssertEqual(d.lost(), .left)
        XCTAssertNil(d.lost())
    }

    func testTicksOncePerWholeDegree() {
        var t = DegreeTicker(config: config)
        XCTAssertNil(t.update(tilt: 5, aim: 0, at: 0))
        XCTAssertNil(t.update(tilt: 4.5, aim: 0, at: 0.1))
        XCTAssertNotNil(t.update(tilt: 4, aim: 0, at: 0.2))
        XCTAssertNil(t.update(tilt: 3.9, aim: 0, at: 0.3))
        XCTAssertNotNil(t.update(tilt: 3, aim: 0, at: 0.4))
    }

    func testEitherAxisTicks() {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 2, aim: 2, at: 0)
        XCTAssertNotNil(t.update(tilt: 2, aim: 3, at: 0.1))
    }

    func testNoiseAroundADegreeDoesNotTick() {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 3, aim: 0, at: 0)
        for (i, v) in [2.6, 3.4, 2.6, 3.4, 2.6].enumerated() { XCTAssertNil(t.update(tilt: v, aim: 0, at: 0.1 * Double(i + 1))) }
    }

    func testTicksAreRateLimited() {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 5, aim: 0, at: 0)
        XCTAssertNotNil(t.update(tilt: 4, aim: 0, at: 0.10))
        XCTAssertNil(t.update(tilt: 3, aim: 0, at: 0.13))
        XCTAssertNotNil(t.update(tilt: 3, aim: 0, at: 0.20))
    }

    func testTicksGetStrongerNearLevel() throws {
        var t = DegreeTicker(config: config)
        _ = t.update(tilt: 12, aim: 0, at: 0)
        XCTAssertEqual(try XCTUnwrap(t.update(tilt: 11, aim: 0, at: 0.1)), 0.3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(t.update(tilt: 9, aim: 0, at: 0.2)), 0.37, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(t.update(tilt: 1, aim: 0, at: 0.3)), 0.93, accuracy: 0.001)
    }

    func testSuccessOnlyOnce() {
        var g = LevelGuide(captureAngle: 90, config: config)
        var events: [LevelHaptic] = []
        for i in 0...150 { if let e = g.update(gravity: SIMD3(0, -1, 0), rotationRate: .zero, at: Double(i) * 0.02) { events.append(e) } }
        XCTAssertEqual(events, [.success])
        XCTAssertTrue(g.isLevel)
    }

    func testTurningOverAfterLevelWarnsOnce() {
        var g = LevelGuide(captureAngle: 90, config: config)
        for i in 0...60 { _ = g.update(gravity: SIMD3(0, -1, 0), rotationRate: .zero, at: Double(i) * 0.02) }
        XCTAssertEqual(g.update(gravity: SIMD3(0, 1, 0), rotationRate: .zero, at: 1.3), .warning)
        XCTAssertNil(g.update(gravity: SIMD3(0, 1, 0), rotationRate: .zero, at: 1.32))
        XCTAssertEqual(g.pose, .turnOver)
    }

    func testNoTicksWhilePrompting() {
        var g = LevelGuide(captureAngle: 0, config: config)
        for i in 0...20 {
            let a = Double(i) * .pi / 180
            XCTAssertNil(g.update(gravity: SIMD3(sin(a), -cos(a), 0), rotationRate: .zero, at: Double(i) * 0.1))
        }
        XCTAssertEqual(g.pose, .turnSideways)
    }

    func testSmoothingDampsASpike() throws {
        var c = config!; c.smoothing = 0.2
        var g = LevelGuide(captureAngle: 90, config: c)
        for i in 0..<10 { _ = g.update(gravity: SIMD3(0, -1, 0), rotationRate: .zero, at: Double(i) * 0.02) }
        let a = 30 * Double.pi / 180
        _ = g.update(gravity: SIMD3(sin(a), -cos(a), 0), rotationRate: .zero, at: 0.2)
        guard case .aligned(let tilt, _) = try XCTUnwrap(g.pose) else { return XCTFail("expected aligned") }
        XCTAssertLessThan(tilt, 10)
    }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `cd ios/RoamoryKit && swift test --filter LevelGuideTests`
Expected: build error, `cannot find 'LevelDetector' in scope`.

- [ ] **Step 3: Implement `LevelDetector`, `DegreeTicker`, `LevelHaptic` and `LevelGuide`** in `Level/LevelGuide.swift`, following the behavior above. `LevelGuide.isLevel` returns `detector.isLevel`.

- [ ] **Step 4: Run the tests and see them pass**

Run: `cd ios/RoamoryKit && swift test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/RoamoryKit/Sources/RoamoryKit/Level/LevelGuide.swift ios/RoamoryKit/Tests/RoamoryKitTests/LevelGuideTests.swift
git commit -m "iOS: level guide turns motion into ticks, a settled success and a warning"
```

---

### Task 3: Level overlay on the recording screen (app)

**Files:**
- Modify: `ios/Roamory/Roamory/Capture/CameraService.swift` (one published value)
- Create: `ios/Roamory/Roamory/Recording/LevelHaptics.swift`
- Create: `ios/Roamory/Roamory/Recording/LevelMonitor.swift`
- Create: `ios/Roamory/Roamory/Recording/LevelOverlay.swift`
- Modify: `ios/Roamory/Roamory/Recording/RecordingView.swift`

New files are picked up automatically: the project uses synchronized folders.

**Interfaces:**
- Consumes: `LevelConfig`, `LevelPose`, `LevelGuide`, `LevelHaptic` (Tasks 1–2).
- Produces (Task 4 relies on these):
  - `CameraService.captureRotationAngle: Double?` (`@Published private(set)`): the angle `configure(orientation:)` applied to the video output, set when the session starts.
  - `@MainActor final class LevelMonitor: ObservableObject` with `@Published private(set) var pose: LevelPose?`, `@Published private(set) var isLevel: Bool`, `var isAvailable: Bool`, `var fadeDelay: TimeInterval`, `var bubbleRangeDeg: Double`, `func start(captureAngle: Double)` and `func stop()`.
  - `@MainActor final class LevelHaptics` with `func start()`, `func stop()` and `func play(_ haptic: LevelHaptic)`.
  - `struct LevelOverlay: View` with `let pose: LevelPose?`, `let isLevel: Bool` and `let bubbleRangeDeg: Double`.
  - In `RecordingView`: `@StateObject private var level`, `@State private var showLevel`, and a `levelButton` view.

- [ ] **Step 1: `CameraService.captureRotationAngle`.**
  - Add `nonisolated(unsafe) private var appliedRotationAngle: Double?`. It is written in `configure(orientation:)` inside the `if connection … isVideoRotationAngleSupported(angle)` block, on the session queue, the same way `videoDevice` is.
  - Add the published `captureRotationAngle` next to `captureOrientation`, with a doc comment: "The capture rotation the session records at (degrees, horizon-level), fixed when it starts; the level and the landscape layout follow it."
  - In `prepare`, set it inside the existing `if ok && !isReady` branch, next to `captureOrientation = orientation`.
  - Change nothing else in `Capture/`.

- [ ] **Step 2: `LevelHaptics`.**
  - `start()`:
    - On a private serial queue (`DispatchQueue(label: "roamory.level.audio")`), call `try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)`. The audio session calls can block, as `CameraService` notes.
    - If `CHHapticEngine.capabilitiesForHardware().supportsHaptics`, create `CHHapticEngine(audioSession: .sharedInstance())` with `playsHapticsOnly = true` and `isAutoShutdownEnabled = false`. Restart it in `resetHandler`, and start it.
  - `stop()`: stop the engine, then set the flag back to `false` on the same queue.
  - `play`, as transient events:
    - `.tick(i)`: intensity `i`, sharpness `0.4 + 0.6 * i`.
    - `.success`: two events at 0 s and 0.12 s, intensity 1, sharpness 1.
    - `.warning`: one event, intensity 0.5, sharpness 0.2.
  - Without an engine, or when a pattern fails to play:
    - `.tick` → `UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity:)`.
    - `.success` and `.warning` → `UINotificationFeedbackGenerator().notificationOccurred(.success / .warning)`.

- [ ] **Step 3: `LevelMonitor`.**
  - It holds a `CMMotionManager`, `LevelHaptics`, `private let config = try? LevelConfig.bundled()` and an optional `LevelGuide`.
  - `isAvailable` is `config != nil && motion.isDeviceMotionAvailable`. `fadeDelay` and `bubbleRangeDeg` come from `config`, falling back to 1 and 10 when it is nil.
  - `start(captureAngle:)` does nothing if it is not available or is already running. Otherwise it makes a new `LevelGuide`, starts haptics, sets `deviceMotionUpdateInterval = 1 / updateHz` and calls `startDeviceMotionUpdates(to: .main)`. Each sample goes to `guide.update(gravity:rotationRate:at:)` with `motion.gravity`, `motion.rotationRate` and `motion.timestamp`. Then it publishes `pose` and `isLevel`, and plays the returned haptic.
  - `stop()` stops updates and haptics, and resets `pose` to nil and `isLevel` to false.

- [ ] **Step 4: `LevelOverlay`.**
  - **Card:** a centered, dark translucent card (`.black.opacity(0.55)`, rounded) holding a 220 pt ring, a 6 pt stroke and a 44 pt bubble. White normally, `Theme.accent` when `isLevel`.
  - **Bubble offset:** `(x: -tilt, y: -aim) / bubbleRangeDeg * ringRadius`, clamped to the ring. The bubble sits on the high side and moves up when the camera aims up.
  - **Below the ring:** `String(format: "Tilt %.0f° · Aim %.0f°", abs(tilt), abs(aim))` in `.title2.bold().monospacedDigit()`.
  - **Arrows, one per axis, outside tolerance only:**
    - tilt > 1 → `arrow.counterclockwise`, tilt < -1 → `arrow.clockwise`.
    - aim > 1 → `arrow.down`, aim < -1 → `arrow.up`.
  - **Prompt poses:** instead of the ring, show a large `rotate.right` symbol and the exact prompt copy from Global Constraints. `.turnOver` uses `arrow.triangle.2.circlepath`.
  - **`pose == nil`** (no sample yet): show the ring with the bubble centered and no numbers.
  - **Caption:** `Tap to close`, in small text at the bottom of the card.

- [ ] **Step 5: Wire it into `RecordingView`.**
  - **State:** add `@StateObject private var level = LevelMonitor()`, `@State private var showLevel = false` and `@State private var fadeLevel: Task<Void, Never>?`.
  - **Show on start:** in `.task`, after `await camera.prepare(...)`, set `showLevel = true` when `level.isAvailable && camera.captureRotationAngle != nil`.
  - **`.onChange(of: showLevel)`:** when it turns on, `level.start(captureAngle:)` with the capture angle; when it turns off, `level.stop()`.
  - **`.onChange(of: level.isLevel)`:** cancel `fadeLevel`. When level, start a task that sleeps `level.fadeDelay`, then sets `showLevel = false` with animation unless cancelled. A `.warning` sets `isLevel` false, which cancels the fade, so the overlay stays.
  - **Overlay:** in the root `ZStack`, between `CameraPreview` and the controls `VStack`, add `if showLevel { LevelOverlay(...).onTapGesture { showLevel = false }.transition(.opacity) }`. The controls stay above it and tappable.
  - **`levelButton`:** a circle icon button styled like `studioButton`, with symbol `level` and accessibility label `Level the phone`. It sets `showLevel = true`. Show it in the button row only when `level.isAvailable && camera.captureRotationAngle != nil`.
  - **Curtain:** add `|| showLevel` to the curtain's `paused:`.
  - **Leaving:** `backToSetup()` calls `level.stop()` before `camera.shutdown()`. Add `.onDisappear { level.stop() }`.

- [ ] **Step 6: Type-check**

Run: `ios/Roamory/scripts/typecheck.sh`
Expected: `typecheck: ok`.

- [ ] **Step 7: Commit**

```bash
git add ios/Roamory/Roamory/Capture/CameraService.swift ios/Roamory/Roamory/Recording/LevelHaptics.swift ios/Roamory/Roamory/Recording/LevelMonitor.swift ios/Roamory/Roamory/Recording/LevelOverlay.swift ios/Roamory/Roamory/Recording/RecordingView.swift
git commit -m "iOS app: bubble level with haptics when the recording screen opens"
```

---

### Task 4: Landscape recording layout for 16:9 styles

**Files:**
- Modify: `ios/RoamoryKit/Sources/RoamoryKit/Config/CaptureOrientation.swift`
- Modify: `ios/RoamoryKit/Tests/RoamoryKitTests/CaptureOrientationTests.swift`
- Create: `ios/Roamory/Roamory/App/OrientationLock.swift`
- Modify: `ios/Roamory/Roamory/App/RoamoryApp.swift`
- Modify: `ios/Roamory/Roamory/Recording/RecordingView.swift`
- Modify: `ios/Roamory/Roamory/Recording/CameraPreview.swift` (doc comment only)
- Modify (one line, twice): `ios/Roamory/Roamory.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CameraService.captureRotationAngle`, `levelButton` (Task 3).
- Produces:
  - `public enum InterfaceSide: Sendable, Equatable { case portrait, landscapeLeft, landscapeRight }` (UIKit interface-orientation naming).
  - `CaptureOrientation.interfaceSide(forCaptureAngle: Double) -> InterfaceSide` (`public static`).
  - `final class AppDelegate: NSObject, UIApplicationDelegate`.
  - `@MainActor enum OrientationLock` with `static private(set) var mask: UIInterfaceOrientationMask` and `static func set(_ side: InterfaceSide)`.

- [ ] **Step 1: Write the failing test** in `CaptureOrientationTests.swift`

```swift
func testInterfaceSideForCaptureAngle() {
    // Capture 0° is the phone's top to the left, which UIKit calls interface landscape right.
    XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 0), .landscapeRight)
    XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 180), .landscapeLeft)
    XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 175), .landscapeLeft)
    XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 90), .portrait)
    XCTAssertEqual(CaptureOrientation.interfaceSide(forCaptureAngle: 270), .portrait)   // no upside-down UI on iPhone
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `cd ios/RoamoryKit && swift test --filter CaptureOrientationTests`
Expected: build error, `type 'CaptureOrientation' has no member 'interfaceSide'`.

- [ ] **Step 3: Implement `InterfaceSide` and `interfaceSide(forCaptureAngle:)`.** The nearest of 0/90/180/270 decides; reuse the private `distance`.

- [ ] **Step 4: Run the tests and see them pass**

Run: `cd ios/RoamoryKit && swift test`
Expected: all tests pass.

- [ ] **Step 5: Allow landscape on iPhone, staging only that line.** In both build configurations, change `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;` to `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";`. Apply it to the working copy and to the index separately, so the local signing changes stay unstaged:

```bash
f=ios/Roamory/Roamory.xcodeproj/project.pbxproj
old='INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;'
new='INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";'
sed -i '' "s/$old/$new/" "$f"
git show HEAD:"$f" | sed "s/$old/$new/" > "$TMPDIR/pbxproj.staged"
git update-index --cacheinfo 100644,"$(git hash-object -w "$TMPDIR/pbxproj.staged")","$f"
git diff --cached --stat   # expect: project.pbxproj | 4 ++--
git diff "$f"              # expect: only DEVELOPMENT_TEAM / PRODUCT_BUNDLE_IDENTIFIER lines left unstaged
```

- [ ] **Step 6: `OrientationLock` and the app delegate** in `App/OrientationLock.swift`.
  - `mask` starts as `.portrait`. `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` returns `OrientationLock.mask`.
  - `set(_:)` maps `.portrait` → `.portrait`, `.landscapeLeft` → `.landscapeLeft` and `.landscapeRight` → `.landscapeRight`, and returns early if the mask is unchanged. For each connected `UIWindowScene`, it calls `keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()` and then `requestGeometryUpdate(.iOS(interfaceOrientations: mask))`.
  - In `RoamoryApp`, add `@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`.

- [ ] **Step 7: Lock the recording screen to the capture side.** In `RecordingView`:
  - In `.task`, after `prepare`, call `OrientationLock.set(CaptureOrientation.interfaceSide(forCaptureAngle: angle))` when `camera.captureRotationAngle` is set.
  - In `backToSetup()`, call `OrientationLock.set(.portrait)` before `onBackToSetup()`.
  - Also call it in `.onDisappear`.
  - Update the `CameraPreview` doc comment: the UI is no longer portrait only.

- [ ] **Step 8: Landscape chrome.**
  - Add `@Environment(\.verticalSizeClass) private var verticalSizeClass`. Use `landscapeChrome` when it is `.compact`, otherwise today's controls `VStack` (renamed `portraitChrome`, unchanged in layout).
  - Pull the saving timer, the Evaluate summary card and the status message out of that `VStack` into computed views (`savingTimer`, `summaryCard`, `messageText`), so both layouts use them.
  - `landscapeChrome` is an `HStack`:
    - **Leading:** a `VStack(alignment: .leading)` with `savingTimer` and `formatBadge` in a row at the top (leading padding 60, clear of the back button), a `Spacer`, then `guidedAccessHint` (max width 420), `summaryCard` and `messageText`.
    - **Trailing:** a `VStack(spacing: 12)` with, top to bottom: the debug settings and Evaluate buttons, `levelButton`, `saveButton`, `studioButton` and `zoomColumn`. Padding 16 on the trailing edge, 12 vertical.
  - **`zoomColumn`:** a `VStack` of the zoom preset buttons, with no rotary dial (pinch still zooms). Factor the button out of `zoomPicker` as `zoomPresetButton(_ zoom: CGFloat, isActive: Bool, size: CGFloat)` and use it in both.

- [ ] **Step 9: Type-check, and build if this Mac's Xcode can**

Run: `ios/Roamory/scripts/typecheck.sh`
Expected: `typecheck: ok`.
Then run: `cd ios/Roamory && xcodebuild build -scheme Roamory -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`. If Xcode cannot open the project format, note that and rely on the type-check.

- [ ] **Step 10: Commit** (the pbxproj line is already staged from Step 5)

```bash
git add ios/RoamoryKit/Sources/RoamoryKit/Config/CaptureOrientation.swift ios/RoamoryKit/Tests/RoamoryKitTests/CaptureOrientationTests.swift ios/Roamory/Roamory/App/OrientationLock.swift ios/Roamory/Roamory/App/RoamoryApp.swift ios/Roamory/Roamory/Recording/RecordingView.swift ios/Roamory/Roamory/Recording/CameraPreview.swift
git diff --cached --name-only   # project.pbxproj is listed; check that git diff still shows the signing lines unstaged
git commit -m "iOS app: landscape recording layout for 16:9 styles, controls in a right-hand column"
```

---

### Task 5: Docs, phone check, PR

**Files:**
- Modify: `CLAUDE.md` (the iOS app bullet under Commands)

- [ ] **Step 1: Update `CLAUDE.md`.** After "Start opens the camera with the screen dark, hold to wake.", add: "A bubble level shows over the preview when the camera opens, with haptic ticks while turning and a double tap once the phone is level and still; it fades out after, and the level button brings it back. 16:9 styles lay the recording screen out in landscape with the controls in a right-hand column." Commit it: `git commit -am` is not allowed because of the pbxproj, so stage `CLAUDE.md` alone. Subject: `CLAUDE.md: mount level and landscape recording`.

- [ ] **Step 2: Run all checks**

Run: `cd ios/RoamoryKit && swift test && cd ../.. && ios/Roamory/scripts/typecheck.sh`
Expected: all tests pass, then `typecheck: ok`.

- [ ] **Step 3: Phone check (by the user).** Hand the user this checklist and wait for the results. Fix anything that fails in the task that owns it.
  1. **Reels trip, phone upright:** the level shows, ticks are felt while tilting, and the double tap comes after about 1 s held level. The overlay fades, and the level button brings it back.
  2. **Reels trip, phone sideways:** `Hold the phone upright` shows.
  3. **Cinematic trip, Start with the phone upright:** the interface turns landscape with the phone's top to the left. The column is on the right, the preview is upright, and so are the bubble and arrows (raising the right side reduces tilt).
  4. **Same trip, phone turned the other way:** `Turn the phone the other way round` shows. Back upright: `Turn the phone sideways` shows.
  5. **While the level shows:** Save buffer and a volume key both start saving. The clip in Photos is the right way up.
  6. **Back to setup from the landscape trip:** setup is portrait again.
  7. **Make video sheet in landscape:** it opens and is usable.

- [ ] **Step 4: Push and open the PR to `dev`**

First ask the user to confirm opening the PR and for Yifan's GitHub login (do not guess it); add them afterwards with `gh pr edit --add-reviewer <login>`.

```bash
git push -u origin ios/mount-level
gh pr create --base dev --title "iOS app: mount level and landscape recording layout" --body-file <(cat <<'EOF'
Adds a bubble level with haptic guidance over the camera preview when the recording screen opens, and a landscape layout of the recording screen for 16:9 styles.

- Spec: docs/superpowers/specs/2026-10-24-mount-level-design.md
- Plan: docs/superpowers/plans/2026-10-24-mount-level.md
- Leveling logic and tuning (level_config.json) are in RoamoryKit with tests.
- Capture: one read-only value, `CameraService.captureRotationAngle`; nothing else in Capture/ changes. Yifan, please review that part.
- Haptics are allowed during recording only while the level shows; the buzz can be picked up by the mic in those seconds.
- Known limitation: a Reels trip started upside down shows mirrored arrows (no upside-down UI on iPhone).

Tests: `swift test` and `typecheck.sh` pass; checked on an iPhone (Reels and Cinematic).
EOF
)
```
