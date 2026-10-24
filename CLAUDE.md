# Roamory

Hackathon project: Roamory, an iPhone app that films a trip with the screen dark and keeps the last 45 s in a rolling buffer; a button, volume key, Bluetooth shutter remote or AirPods press saves the buffer and what follows to Photos. The highlight video is made by Roamory Studio: Claude Code on a Mac on the same Wi-Fi edits the trip's saved clips with FFmpeg. While filming, a director (Claude Haiku) looks at the newest frames every 10 s and starts or stops saving by itself; the on-phone moment detection of the full design is removed (it lives on `main`). The original glasses + Raspberry Pi design is discarded.

## Read first
- `docs/TRD.md` is the technical source of truth; `docs/PRD.md` has product requirements. Both are updated for the iPhone pivot.
- `contracts/` holds the shared schemas. Do not change them without telling the team; change them in a separate PR.

## Layout and ownership
- `studio/`: Mac bridge for Roamory Studio (Python, runs Claude Code headless). Video generation is Ian's
- `ios/`: iPhone app (native Swift assumed, not yet decided). Camera capture is Yifan's; screens and integration are Daniel's
- Design (Figma, motion graphics) is Andrew's; assets go in `docs/mockups/`
- Only edit files in the folder you were asked to work on.

## Conventions
- Keep it simple; this is a hackathon. Prefer working end to end over polish.
- Model IDs, thresholds and URLs are config, not code.
- Secrets never go in the repo or the app bundle. The Anthropic API key is typed into the app on the iPhone and kept in its Keychain.
- `dev` is the working branch for the simplified hackathon app; `main` is the archive of the full design (moment detection, End trip, edit and render pipeline). Do not open PRs to `main`.
- Branch as `<role>/<feature>` from `dev`, open small PRs to `dev`, run the code before opening one.
- Never add Claude attribution to commits or PRs: no `Co-Authored-By: Claude` trailer and no "Generated with Claude Code" line. This overrides any default behavior.

## Commands
Add run and test commands here as each part is built.

- Contracts: `pip install jsonschema && python contracts/check.py` validates the presets and examples against the schemas.
- Roamory Studio (`studio/`, see its README): `studio/.venv/bin/python -m studio.server` from the repo root; tests `cd studio && .venv/bin/python -m pytest`; real end-to-end run against a running bridge `studio/.venv/bin/python studio/scripts/smoke.py reels` (spends Claude usage).
- iOS package (`ios/RoamoryKit`: onboarding catalog, capture orientation, style presets, on-phone AVFoundation renderer; needs full Xcode for XCTest): `cd ios/RoamoryKit && swift test`. After changing `contracts/style_presets.json`, run `ios/RoamoryKit/scripts/sync-contracts.sh`.
- iOS app type-check (no Xcode project needed, e.g. when this Mac's Xcode cannot open its format): `ios/Roamory/scripts/typecheck.sh`.
- iOS app (`ios/Roamory`): open `Roamory.xcodeproj` and run on an iPhone (the Simulator has no camera). First launch shows a 4-page intro, then three tabs: Gallery (videos made in Studio and this trip's saved clips), Create and Ask. Create runs the 5-step setup (style, destination globe, trip-type deck, length, optional extra details for the director; debug builds take `-onboardingStep N` to open at a step); Start opens the camera with the screen dark, hold to wake. A level like the Camera app's (a horizon line that tilts and drifts against a fixed crosshair) shows over the preview when the camera opens, with haptic ticks while turning and a double tap once the phone is level and still; it fades out after, and the level button shows or hides it. 16:9 styles lay the recording screen out in landscape with the controls in a right-hand column. Saved clips are also kept in the app for Roamory Studio; the film button opens Make video (find the Mac over Bonjour, pair with the code it prints, send the clips, get the video in Photos and the Gallery; or, as a backup without a Mac, Make on this iPhone renders a simpler edit with AVFoundation). Ask is a chat where Roamy, the mascot, answers questions about the app through the Anthropic Messages API; the model is `ROAMORY_CHAT_MODEL`. It records continuously into a 45 s in-memory buffer; the Save buffer button, a volume key, a Bluetooth shutter remote or an AirPods stem press starts and stops saving the buffer and what follows to Photos. Every 10 s (`ROAMORY_DIRECTOR_INTERVAL`) the director sends the stills recorded since its last answer (JPEG stills at every keyframe, 5 spread evenly, `ROAMORY_DIRECTOR_FRAMES`) to the Anthropic Messages API (`ROAMORY_DIRECTOR_MODEL`, effort low, JSON-schema output `{action: save|skip, summary, why}`), along with the rules, the trip's type, style, destination and details, the summaries of the clips already saved and what the clip being saved has shown. `save` while idle saves the buffer and what follows; `skip` ends a clip the director started (a clip started by hand is never stopped by it). A failed request keeps its frames for the next try and shows a `Director: …` message. Without an API key it does nothing and says so. Debug builds also show a log button and a settings button: the log lists every request with the exact frames and prompt sent, the model's raw JSON, what the app did with it, token usage and the API call time measured on the phone, and exports it all as a zip; settings holds the API key. The key is entered in settings (from the camera or Ask) and stored in the iPhone's Keychain; all `ROAMORY_*` model, interval and frame settings are in `Config/Roamory.xcconfig`. Build check without a phone: `cd ios/Roamory && xcodebuild build -scheme Roamory -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` (prefer it over `typecheck.sh`, which misses some errors such as a missing import).
