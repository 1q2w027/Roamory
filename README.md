# Roamory (AI Travel Videographer)

Hackathon MVP: an iPhone app that learns your video style and trip, films with the screen dark and an adaptive frame rate, keeps the moments that matter (a Bluetooth button guarantees one), and auto-edits a highlight video. Cloud AI selects the moments.

![Roamory iPhone mockups](docs/mockups/iphone-screens.png)

*Rough mockups: style picker, map destination, trip type, recording mode. Source: [docs/mockups/iphone-screens.html](docs/mockups/iphone-screens.html).*

> The PRD is updated for the iPhone pivot. The TRD and the repo layout below still describe the old glasses design and are being rewritten.

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
