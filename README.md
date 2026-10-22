# Roamory (AI Travel Videographer)

Hackathon MVP: camera glasses with a rolling buffer, an AI backend that picks meaningful moments, and an auto-edited highlight video.

Specs live in `docs/`: [PRD](docs/PRD.md) · [TRD](docs/TRD.md). The TRD is the source of truth for architecture.

## Repo layout

| Folder | What | Owner |
| --- | --- | --- |
| `glasses-agent/` | Raspberry Pi recorder, ring buffer, control server | TBD (hardware/edge) |
| `backend/` | FastAPI, detection cascade, FFmpeg render | TBD (AI) / TBD (backend+video) |
| `web/` | Next.js mobile web app | TBD (frontend) |
| `contracts/` | Shared JSON schemas and API shapes | Everyone, via PR |
| `docs/` | PRD, TRD, `DECISIONS.md` | Lead |

## Workflow

1. Never push to `main`. Branch as `<role>/<feature>` (e.g. `backend/stage1-filter`).
2. Open a small PR at least every 1-2 hours. Run your code before asking for review.
3. Change `contracts/` only in its own PR so everyone sees it.
4. Work from the board's issues; one owner each.
5. Secrets go in `.env` (copy `.env.example`). Never commit them.

## Getting started

Setup steps for each folder go here as they are built.
