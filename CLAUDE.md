# Roamory

Hackathon project (36 hours): AI Travel Videographer. Camera glasses (Raspberry Pi Zero 2 W) keep a rolling video buffer, a FastAPI backend runs a gated model cascade to pick moments, FFmpeg renders a highlight MP4, and a Next.js mobile web app controls it.

## Read first
- `docs/TRD.md` is the technical source of truth; `docs/PRD.md` has product requirements.
- `contracts/` holds the shared schemas. Do not change them without telling the team; change them in a separate PR.

## Layout and ownership
- `glasses-agent/`: Python 3.11, Picamera2, ring buffer, port 8081 control server
- `backend/`: Python 3.11, FastAPI, SQLite, OpenCLIP, FFmpeg
- `web/`: Next.js (App Router) + Tailwind
- Only edit files in the folder you were asked to work on.

## Conventions
- Keep it simple; this is a hackathon. Prefer working end to end over polish.
- Model IDs, thresholds and URLs are config, not code.
- Secrets live in `.env` (see `.env.example`); never commit them or put them in the web bundle.
- Branch as `<role>/<feature>`, open small PRs to `main`, run the code before opening one.

## Commands
Add run and test commands here as each part is built.
