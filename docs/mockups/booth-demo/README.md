# Booth demo video: how Roamory works

A silent 30 s loop for the hackathon booth, made with [HyperFrames](https://hyperframes.heygen.com) (HTML + GSAP rendered to MP4). Design: `docs/superpowers/specs/2026-10-24-booth-demo-video-design.md`. The approved keyframes are in `keyframes.html` (open it in a browser).

- `index.html` mounts one scene, `compositions/film.html`, which holds everything: the 3D phone, Roamy, the headlines and every beat. One scene keeps the phone and Roamy moving continuously across beats.
- `assets/beats.js` is the one place beat timings and headline copy live. Change them there only.
- `assets/footage/` holds the travel clips used inside the phone; each one is credited in `CREDITS.md`.

## Commands

Run from this folder. Needs Node 22+ and FFmpeg (`brew install ffmpeg`); `npx hyperframes browser ensure` once if Chrome is missing.

```bash
node --test scripts/*.test.mjs          # beat timing rules
bash scripts/lint-rules.sh              # project rules (no clocks or CSS animation, no web fonts, credited footage)
npx hyperframes check --json            # HyperFrames lint, runtime, layout and contrast
npx hyperframes snapshot --at 2,12,22   # PNG frames in .hyperframes/artifacts/snapshots/
npx hyperframes preview --background    # live preview in the browser
npx hyperframes render --quality delivery --output roamory-how-it-works.mp4
bash scripts/verify.sh roamory-how-it-works.mp4   # 1920x1080, 30 fps, silent, 30–36 s, seamless loop
```

To play it at the booth: `ffplay -loop 0 -fs roamory-how-it-works.mp4`, or QuickTime with View > Loop.
