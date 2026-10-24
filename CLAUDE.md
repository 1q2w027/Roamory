# Roamory

Hackathon project: Roamory, an iPhone app that films a trip with the screen dark and keeps the last 45 s in a rolling buffer; a button, volume key, Bluetooth shutter remote or AirPods press saves the buffer and what follows to Photos. Moment selection, editing and rendering are removed for now; the product keeps only recording and saving video. The original glasses + Raspberry Pi design is discarded.

## Read first
- `docs/TRD.md` is the technical source of truth; `docs/PRD.md` has product requirements. Both are updated for the iPhone pivot.
- `contracts/` holds the shared schemas. Do not change them without telling the team; change them in a separate PR.

## Layout and ownership
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
- iOS package (`ios/RoamoryKit`: onboarding catalog, capture orientation, style presets; needs full Xcode for XCTest): `cd ios/RoamoryKit && swift test`. After changing `contracts/style_presets.json`, run `ios/RoamoryKit/scripts/sync-contracts.sh`.
- iOS app type-check (no Xcode project needed, e.g. when this Mac's Xcode cannot open its format): `ios/Roamory/scripts/typecheck.sh`.
- iOS app (`ios/Roamory`): open `Roamory.xcodeproj` and run on an iPhone (the Simulator has no camera). Launch runs the 4-step setup (style, destination globe, trip-type deck, length; debug builds take `-onboardingStep N` to open at a step); Start opens the camera with the screen dark, hold to wake. It records continuously into a 45 s in-memory buffer; the Save buffer button, a volume key, a Bluetooth shutter remote or an AirPods stem press starts and stops saving the buffer and what follows to Photos. Debug builds also show an Evaluate button and a key button: Evaluate sends 6 frames from the buffer (JPEG stills taken at every keyframe) straight to the Anthropic Messages API and shows Claude's description on screen (tap to dismiss). The API key is entered in the app (key button, or the first Evaluate press) and stored in the iPhone's Keychain; the model is `ROAMORY_SUMMARY_MODEL` in `Config/Roamory.xcconfig`. Build check without a phone: `cd ios/Roamory && xcodebuild build -scheme Roamory -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`.
