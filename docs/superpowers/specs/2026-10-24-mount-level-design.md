# Mount Level and Landscape Recording Layout — Design

Status: approved design (2026-10-24). Plan: `docs/superpowers/plans/2026-10-24-mount-level.md`.

## Intent

Roamory films a trip from a phone worn on a **chest mount**. After clipping the phone in, the user has no
easy way to tell whether it is level, so the footage comes out tilted. On the mount the screen faces the
user's chest and is **only partly visible** from above, so the user should be able to level the phone
mostly **by feel**: haptics while the angle changes, and a distinct feel when it reaches the right angle.

Second, while recording in a 16:9 style the on-screen controls are laid out for an upright phone, because
the app is portrait-only on iPhone. They should be laid out for a sideways phone.

## Goals

1. **Level overlay on the recording screen**, drawn over the camera preview, with haptic guidance.
2. **Landscape layout of the recording screen** for 16:9 styles.

## Non-goals

- No software horizon correction or cropping of the recorded video. The level only guides the user.
- No change to how capture orientation is chosen (Reels 9:16 portrait; Cinematic, Documentary and Vlog
  16:9 landscape; fixed when the camera session starts, TRD 4.1).
- No landscape layout anywhere else in the app (setup, Gallery, Ask stay portrait).
- No change to `contracts/`.

## Anti-goals (a failure even if it technically works)

- Haptics that buzz constantly from hand tremor or mount wobble, or a success feel that fires repeatedly.
- An overlay that blocks the Save button or the volume-key/remote/AirPods save path.
- Footage or the 45 s buffer interrupted by the level or by the layout rotation.

## Part 1: Mount level

### What the user decided
- **Shape: a 2-axis bubble level** (bubble in a circle) with the two angles as numbers under it
  (e.g. "Tilt 3° · Aim 5°"). Picked from mockups over a horizon line and an edge ruler.
- **Both axes** are leveled:
  - *Tilt* (roll): rotation about the lens axis, i.e. how tilted the horizon is in the footage.
  - *Aim* (pitch): camera pointing up or down.
- **Reference is the trip's capture orientation**: Reels levels against an upright phone; the 16:9 styles
  against a phone on its side (the side the session records, see below).
- **When it shows:** it appears over the preview when the recording screen opens, and **disappears once the
  phone is level** (after the success haptic). The buffer keeps recording the whole time.
- **Haptics**: felt while the angle changes, and a distinct feel when the best angle is found.
- Screen is partly visible on the mount, so the visual must be readable at a glance from an angle.

### Calls I made (the user can override)
- **Target is 0° tilt and 0° aim** (camera looking straight ahead; a chest mount is already at a useful height).
- **Level = both axes within ±1° with the phone still, held for 1 s** (see "Success needs a settled phone"). Then: success haptic (a sharp double tap, clearly
  different from the ticks), bubble and ring turn the key color `#03fc73` (`Theme.accent`), and the overlay
  fades out about 1 s later.
- **Ticks:** a light tick each time either angle crosses a whole degree. Ticks get stronger and crisper the
  closer the phone is to 0° (felt as "warmer"). Ticks only while the overlay is showing.
- **Leaving level** before the overlay has faded out: one light warning tap; the overlay stays.
- **Visual:** large, thick, high-contrast bubble and ring on a dark translucent backing, big numbers, and an
  arrow per axis showing which way to turn. Drawn in the user's frame (upright text in portrait, sideways
  layout in landscape per Part 2).
- **Level is measured against the side the session records**, not either side. `CameraService` fixes the
  capture rotation once at start (`rotationAngle(near:)`: 0° or 180° for 16:9, 90° or 270° for Reels) and
  never changes it, so a phone mounted the other way round records upside down. Starting from an upright
  phone, a 16:9 trip records at 0°.
- **Wrong way round:** instead of the bubble, show a large prompt. The bubble appears once the phone is turned.
  - Wrong orientation (per `CaptureOrientation.isHeld(at:)`): "Turn the phone sideways" or "Hold the phone
    upright", the same text as today's `formatLine`.
  - Right orientation but upside down from the recorded side: "Turn the phone the other way round".
- **Success needs a settled phone:** counting starts only once the phone is the right way round. Level means
  both axes within ±1° **and** the phone still (low rotation rate) for 1 s, so passing through level while
  clipping the phone in does not count.
- **Haptics while recording:** iOS mutes haptics while the audio session records unless
  `AVAudioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)` is set. Turn it on while the level
  overlay shows and off when it closes, set after `CameraService.prepare` has configured the audio session.
  The buzz may be picked up by the mic during those seconds. The Vlog style keeps original audio, so it can
  end up in a Vlog edit if that pre-roll is saved. Accepted, because leveling happens right after mounting.
- **Bring it back:** a small level button in the control set reopens the overlay (for when the mount slips).
  Tapping the overlay dismisses it without leveling.
- **No level sensor** (CoreMotion device motion unavailable): no overlay, no level button.
- **No Core Haptics** support: the visual still works; fall back to `UIImpactFeedbackGenerator` taps.
- **Dark curtain** (`RecordingView.curtainEnabled`, currently `false` for debugging): if enabled, the curtain
  does not cover the screen while the level overlay is showing.
- **Tech:** CoreMotion device motion (`gravity`) at ~30–60 Hz, lightly smoothed. The gravity → (tilt, aim)
  math, the ±1° / still for 1 s level detector and the degree-crossing tick logic are pure code in RoamoryKit with
  XCTest; the motion source, haptics engine and SwiftUI overlay live in the app (`ios/Roamory/Roamory/Recording/`).
  Core Haptics for ticks (intensity/sharpness per tick) and the success pattern.

## Part 2: Landscape layout for 16:9 styles

### What the user decided
- In a 16:9 style the recording screen is laid out for a sideways phone with the **controls in a vertical
  column along the right edge** (picked from mockups over a bottom row and over rotating icons only):
  settings / evaluate (debug builds), Save buffer, Make video (film), zoom presets, and the level button.
  Back button, format badge and saving timer along the top-left. Text reads horizontally.

### Calls I made
- Reels (9:16) keeps today's portrait layout unchanged.
- The rest of the app stays portrait-only. Only the recording screen of a 16:9 trip turns landscape; going
  back to setup returns to portrait.
- The landscape interface is locked to the side the session records (see Part 1), so on a correctly
  mounted phone the column is on the right as the user sees it.
- Sheets opened from the recording screen (Make video, debug settings) and the Back confirmation follow the
  screen's orientation.
- The Guided Access hint, Evaluate summary and status messages are laid out to fit landscape.
- The camera preview must stay level in both layouts. `CameraPreview` already follows the phone with a
  `RotationCoordinator` built on the preview layer; verify on a phone that it is still upright once the
  interface itself rotates.

## Constraints

- Work only in `ios/`. Native Swift / SwiftUI, iOS 26 SDK as in `ios/Roamory/scripts/typecheck.sh`.
- Branch `ios/mount-level` from `dev`, small PR to `dev`. No Claude attribution in commits or PRs. English only on GitHub.
- `project.pbxproj` has local, uncommitted signing changes (team, bundle id). Don't commit those. Landscape
  support needs `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` to include landscape, so commit only
  that line.
- `RecordingView` and `CameraService` were written by Yifan (capture); the screen changes are Daniel's.
  Approved by the user: add one read-only `@Published private(set) var captureRotationAngle: Double?` to
  `CameraService`, set to the angle `configure(orientation:)` applies. Nothing else in capture changes. Name
  Yifan as a reviewer on the PR.
- Checks: `cd ios/RoamoryKit && swift test`; `ios/Roamory/scripts/typecheck.sh` → `typecheck: ok`; on an
  iPhone (the Simulator has no camera or motion) for haptics, leveling and both layouts.

## Left to the builder

- Exact bubble range (how many degrees the bubble's travel covers before it pins to the ring), smoothing
  constant, tick intensity curve and the Core Haptics pattern parameters.
- How the zoom picker/dial is arranged in the right-hand column.
- How the landscape lock is implemented (e.g. an app delegate `supportedInterfaceOrientations` switch plus
  `UIWindowScene.requestGeometryUpdate`).
- File split inside `Recording/` and RoamoryKit.

## Verification

- RoamoryKit XCTest covers the pure logic: gravity → tilt/aim for portrait and both landscape sides, the
  upside-down case, the ±1° + still for 1 s detector (incl. passing through level while moving does not
  count), and degree-crossing ticks.
- `ios/Roamory/scripts/typecheck.sh` prints `typecheck: ok`.
- On an iPhone, for one Reels trip and one 16:9 trip:
  - Ticks are felt while turning, the success double tap once on level, and the overlay fades.
  - The level button brings the overlay back.
  - The wrong-way prompts appear correctly.
  - The 16:9 layout has the controls in a right-hand column, and the preview is upright.
  - Back to setup returns to portrait.
  - A clip saved during leveling still lands in Photos, the right way up.
