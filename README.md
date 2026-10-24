# Roamory (AI Travel Videographer)

Hackathon MVP: an iPhone app that learns your video style and trip, films with the screen dark and an adaptive frame rate, keeps the moments that matter (a Bluetooth button guarantees one), and auto-edits a highlight video. Cloud AI selects the moments.

![Roamory iPhone mockups](docs/mockups/iphone-screens.png)

*Rough mockups: style picker, map destination, trip type, recording mode. Source: [docs/mockups/iphone-screens.html](docs/mockups/iphone-screens.html).*

Specs live in `docs/`: [PRD](docs/PRD.md) · [TRD](docs/TRD.md). Both are updated for the iPhone pivot.

## Repo layout

| Folder | What | Owner |
| --- | --- | --- |
| `ios/` (camera) | iPhone camera capture, adaptive frame rate, rolling buffer | Yifan |
| `ios/` (screens) | iPhone app UI: onboarding, trip setup, recording mode, review screen; putting all parts together | Daniel |
| `backend/` (detection) | Cloud service: real-time moment selection with a frontier model (keeps API keys off the phone) | Daniel |
| `render/` (video) | Final highlight video: a Claude agent picks, edits and renders it with Remotion | Ian |
| Figma / motion graphics | App design and demo motion graphics (assets go in `docs/mockups/`) | Andrew |
| `contracts/` | Shared JSON schemas and API shapes between the app and the backend | Everyone, via PR |
| `docs/` | PRD, TRD, `DECISIONS.md`, mockups | Daniel |

## Who does what

- **Yifan:** use the iPhone camera for our app (capture side).
- **Daniel:** AI that detects important scenes in real time, plus the app frontend and putting everything together.
- **Ian:** AI that makes the final highlight video.
- **Andrew:** Figma design and motion graphics for the demo.

`ios/` is shared by Yifan (camera) and Daniel (screens); split work by subfolder to avoid conflicts. Yifan and Daniel agree how captured frames and clips reach the backend, and write it in `contracts/`.

## Workflow

1. Never push to `main`. Branch as `<role>/<feature>` (e.g. `ios/rolling-buffer`).
2. Open a small PR at least every 1-2 hours. Run your code before asking for review.
3. Change `contracts/` only in its own PR so everyone sees it.
4. Work from GitHub issues, one owner each (none yet; the TRD §12.1 gates are a good first list).
5. Secrets go in `.env` (copy `.env.example`). Never commit them.

## Getting started

Setup steps for each folder go here as they are built.

## Idea Note

magsafe + mount -> automatically opens apps
