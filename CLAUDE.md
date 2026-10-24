# Roamory

Hackathon project: Roamory, an iPhone app that films a trip with the screen dark and an adaptive frame rate, keeps the moments that matter in a rolling buffer, uses cloud AI (frontier model API) to select moments, and produces a highlight video the user reviews in the app. A Bluetooth button guarantees a moment is kept. The original glasses + Raspberry Pi design is discarded.

## Read first
- `docs/TRD.md` is the technical source of truth; `docs/PRD.md` has product requirements. Both are updated for the iPhone pivot.
- `contracts/` holds the shared schemas. Do not change them without telling the team; change them in a separate PR.

## Layout and ownership
- `ios/`: iPhone app (native Swift assumed, not yet decided). Camera capture is Yifan's; screens and integration are Daniel's
- `backend/`: Python 3.11, FastAPI; cloud moment selection via a frontier model API (render location not yet decided). Detection is Daniel's; final video generation is Ian's
- `render/`: Node 22, Remotion; optional cloud video renderer behind `POST /v1/render` (TRD §9.2, `docs/remotion-plan.md`). Ian's
- Design (Figma, motion graphics) is Andrew's; assets go in `docs/mockups/`
- Only edit files in the folder you were asked to work on.

## Conventions
- Keep it simple; this is a hackathon. Prefer working end to end over polish.
- Model IDs, thresholds and URLs are config, not code.
- Secrets live in `.env` (see `.env.example`); never commit them or put them in the app bundle.
- Branch as `<role>/<feature>`, open small PRs to `main`, run the code before opening one.
- Never add Claude attribution to commits or PRs: no `Co-Authored-By: Claude` trailer and no "Generated with Claude Code" line. This overrides any default behavior.

## Commands
Add run and test commands here as each part is built.

- Contracts: `pip install jsonschema && python contracts/check.py` validates the presets and examples against the schemas.
- Backend setup: `cd backend && python3.11 -m venv .venv && .venv/bin/pip install -e ".[dev]"` (reads the repo-root `.env`).
- Backend tests: `cd backend && .venv/bin/pytest`.
- Backend run: `cd backend && .venv/bin/uvicorn app.main:app --reload`. Try it: `curl -H "Authorization: Bearer $APP_TOKEN" -F "request=@../contracts/examples/plan_request_reels.json" -F "m_01_0.jpg=@thumb.jpg" … localhost:8000/v1/plan` (one `{moment_id}_{k}.jpg` part per thumbnail).
- Try `/v1/evaluate`: `curl -H "Authorization: Bearer $APP_TOKEN" -F "context=@../contracts/examples/evaluate_context_select.json" -F "frame_0.jpg=@f0.jpg" -F "frame_1.jpg=@f1.jpg" -F "frame_2.jpg=@f2.jpg" localhost:8000/v1/evaluate` (1-3 JPEG frames, oldest first).
- iOS Edit package (`ios/RoamoryKit`, needs full Xcode for XCTest): `cd ios/RoamoryKit && swift test` on the Mac, or `xcodebuild test -scheme RoamoryKit -destination 'platform=iOS Simulator,name=iPhone 17'`. After changing `contracts/style_presets.json`, run `ios/RoamoryKit/scripts/sync-contracts.sh`.
- iOS app type-check (no Xcode project needed, e.g. when this Mac's Xcode cannot open its format): `ios/Roamory/scripts/typecheck.sh`. Saved moment clips land in `Documents/trips/{tripId}/clips/` (Files > On My iPhone > Roamory).
- Render service (`render/`, phase R1 of `docs/remotion-plan.md`): `cd render && npm ci && npm test`; `scripts/sync-assets.sh` copies the music and sample clips into `render/public/`; run with `npm start` (reads the repo-root `.env`, then `render/.env`); `npm run studio` previews each example; `scripts/smoke.sh [style…]` renders each example spec and checks its size, fps and duration against `contracts/examples/timeline_*.json`. Agent mode (`POST /v1/agent`, phase A1 of `docs/agentic-video-generation.md`): with `npm start` running and `ANTHROPIC_API_KEY` set, `scripts/agent-smoke.sh [style]` runs one real agent job over the sample clips and checks the video (spends API money; needs ffmpeg).
- Backend and render together: `scripts/dev.sh` runs both on this Mac, reachable from the phone (backend :8000, render `$PORT` or :3000); Ctrl-C stops both. The app finds them through `ROAMORY_API_BASE_URL` and `ROAMORY_RENDER_BASE_URL` in `ios/Roamory/Config/Local.xcconfig`.
- Cloud hosting (Fly.io, one app with the backend and render behind Caddy, one always-on machine since budgets and render jobs are in memory): set `FLY_APP` in `.env` and `fly auth login`, then `scripts/cloud-setup.sh` once (creates the app, stores the API key and app token as Fly secrets), `scripts/deploy.sh` to build, push and deploy with `cloud/fly.toml` (run `render/scripts/sync-assets.sh` first), and `scripts/use-cloud.sh` to point the app at `https://$FLY_APP.fly.dev`. Logs: `fly logs -a $FLY_APP`. Local image: `docker build -f cloud/Dockerfile -t roamory .`, run with `-e PORT=8080` since `.env`'s `PORT` is the render service's; `cloud/Caddyfile` routes `/v1/render*` and `/v1/agent*` to render and the rest to the backend.
- Phone to laptop render: `ios/Roamory/Config/use-laptop-render.sh` points the app at this Mac (untracked `Local.xcconfig`), then `cd render && npm start`; Render Lab (Debug corner button) with engine "Remotion".
- iOS app (`ios/Roamory`): open `Roamory.xcodeproj` and run on an iPhone (the Simulator has no camera). Record, keep moments with the bookmark button, a volume key or a Bluetooth shutter remote, then End trip: Processing, then Review. Build check without a phone: `cd ios/Roamory && xcodebuild build -scheme Roamory -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`. In the Simulator the title overlay crashes the AVFoundation render, so test rendering on a phone.
