# Render service

Optional cloud engine for the highlight video (TRD §9.2, `docs/remotion-plan.md`). Remotion renders the whole video from a rebased edit spec; the phone's AVFoundation renderer stays the default and the fallback. The API is in `contracts/README.md` ("Render service: `/v1/render`").

## Run

```sh
npm ci
scripts/sync-assets.sh        # music + sample clips into public/ (from the iOS bundle's Resources)
npm test                      # timeline vs golden timelines, validation, auth, 429, job lifecycle
npm start                     # bundles once, then serves on $PORT (default 3000)
scripts/smoke.sh [style ...]  # renders the examples over the sample clips and checks them with ffprobe
```

### Render from the phone on your laptop

The phone and the Mac must be on the same Wi-Fi.

1. `ios/Roamary/Config/use-laptop-render.sh` writes the app's untracked `Local.xcconfig` with this Mac's `.local` name, `$PORT` and `$APP_TOKEN` (it generates a token into `render/.env` if none is set). Pass a host to override, for example the IP that `npm start` prints when the network blocks Bonjour.
2. `npm start`. It prints the addresses a phone can use. Allow incoming connections if macOS asks about `node`.
3. Build and run the app on the phone from Xcode, then allow local network access when iOS asks. In a Debug build, the corner button opens Render Lab. Pick "Remotion" (or "Both") and render. If the server can't be reached, the summary says "remote failed" and the phone renders the video itself.

Config comes from the repo-root `.env`, then `render/.env`: `APP_TOKEN`, `PORT`, `RENDER_CONCURRENCY`, `RENDER_TTL_S`, `MAX_UPLOAD_MB` (and `RENDER_TMP_DIR`, default the OS temp dir).

The music and sample clips live with the iOS app. Until its Edit branches merge, point the sync at a checkout or build that has them: `IOS_RESOURCES=path/to/Resources scripts/sync-assets.sh`.

Try the API (with the server running):

```sh
curl -H "Authorization: Bearer $APP_TOKEN" -F request=@../contracts/examples/render_request_reels.json \
  -F m_01.mp4=@public/sample/sample_a.mp4 … localhost:3000/v1/render     # one {moment_id}.mp4 per clip
curl -H "Authorization: Bearer $APP_TOKEN" localhost:3000/v1/render/<job_id>
curl -H "Authorization: Bearer $APP_TOKEN" -o out.mp4 localhost:3000/v1/render/<job_id>/video
```

## Layout

| Path | What |
|---|---|
| `src/remotion/timeline.ts` | Port of iOS `EditTimeline` (must match the golden timelines) |
| `src/remotion/layout.ts` | Timeline seconds to frames, rounding each boundary so cuts don't drift |
| `src/remotion/speedRamp.ts` | The 4-step ramp as constant-rate segments, as on iOS |
| `src/remotion/Highlight.tsx` | The composition: clips and transitions, title, captions, end card, music |
| `src/remotion/styles/*.tsx` | Per-style graphics (title, caption, end card) |
| `src/server/` | Express API (`index.ts`), job store and retention (`jobs.ts`), request checks (`validate.ts`), Remotion renderer (`renderer.ts`) |

## Design playground

`npm run studio` opens Remotion Studio with each contract example (`Examples/Example-{style}`) over the sample clips. The graphics for each style are in `src/remotion/styles/`; each exports a `Title`, `Caption` and `EndCard`. Change them freely, but the timing comes from the edit spec: graphics must not change when clips start or end.

## Docker

Build from the repo root, since the service reads `contracts/`: `docker build -f render/Dockerfile -t roamory-render .`, then `docker run --env-file .env -p 3000:3000 roamory-render`.
