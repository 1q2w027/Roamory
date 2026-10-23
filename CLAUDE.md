# Roamory

Hackathon project: Roamory, an iPhone app that films a trip with the screen dark and an adaptive frame rate, keeps the moments that matter in a rolling buffer, uses cloud AI (frontier model API) to select moments, and produces a highlight video the user reviews in the app. A Bluetooth button guarantees a moment is kept. The original glasses + Raspberry Pi design is discarded.

## Read first
- `docs/TRD.md` is the technical source of truth; `docs/PRD.md` has product requirements. Both are updated for the iPhone pivot.
- `contracts/` holds the shared schemas. Do not change them without telling the team; change them in a separate PR.

## Layout and ownership
- `ios/`: iPhone app (native Swift assumed, not yet decided). Camera capture is Yifan's; screens and integration are Daniel's
- `backend/`: Python 3.11, FastAPI; cloud moment selection via a frontier model API (render location not yet decided). Detection is Daniel's; final video generation is Ian's
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
