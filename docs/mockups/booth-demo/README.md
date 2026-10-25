# Booth demo video: how Roamory works

A silent 30 s loop for the hackathon booth, made with [HyperFrames](https://hyperframes.heygen.com) (HTML + GSAP rendered to MP4). Design: `docs/superpowers/specs/2026-10-24-booth-demo-video-design.md`. The approved keyframes are in `keyframes.html` (open it in a browser).

- `index.html` mounts one scene, `compositions/film.html`, which holds everything: the 3D phone, Roamy, the headlines and every beat. One scene keeps the phone and Roamy moving continuously across beats.
- `assets/beats.js` holds the beat windows, headline copy, Roamy's mood per beat and the headline timing and size. The motion inside each beat (camera moves, taps, the strip, the presses) is timed in `compositions/film.html`, so moving a beat means moving its choreography there too. `scripts/structure.test.mjs` fails if the root length, the headline windows or the headline size stop matching `beats.js`.
- `assets/footage/` holds the travel photos used inside the phone and on the film strip; each one is credited in `CREDITS.md`. Several are CC BY-SA, so wherever the MP4 is posted, credit them (see `CREDITS.md`).

## Commands

Run from this folder. Needs Node 22+ and FFmpeg (`brew install ffmpeg`); `npx hyperframes browser ensure` once if Chrome is missing.

```bash
node --test scripts/*.test.mjs          # beat timing, HTML vs beats.js, app copy, loop seam (needs the MP4)
bash scripts/lint-rules.sh              # project rules (no clocks or CSS animation, no web fonts, credited footage)
npx hyperframes check --json            # HyperFrames lint, runtime, layout and contrast
npx hyperframes snapshot --at 2,12,22   # PNG frames in .hyperframes/artifacts/snapshots/
npx hyperframes preview --background    # live preview in the browser
npx hyperframes render --quality delivery --output roamory-how-it-works.mp4
bash scripts/verify.sh roamory-how-it-works.mp4   # 1920x1080, 30 fps, silent, 30–36 s, seamless loop (scripts/seam.sh)
```

To play it at the booth: `ffplay -loop 0 -fs roamory-how-it-works.mp4`, or QuickTime with View > Loop.
