# Booth Demo Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 1920×1080, 30 fps, silent, seamlessly looping ~30 s MP4 that shows how Roamory works, built as a HyperFrames HTML/GSAP composition in `docs/mockups/booth-demo/`.

**Architecture:** One HyperFrames project. The root `index.html` holds the layers that persist across the whole loop (green glow background, the 3D phone shell, Roamy, the headline layer) and one master paused GSAP timeline. Each beat swaps the phone's screen content and adds its own props (film strip, press icons, laptop). Beat timings and headline copy live in one data file, `assets/beats.js`, that both the timeline and a Node test read.

**Tech Stack:** HyperFrames CLI (`npx hyperframes`, npm package `hyperframes` 0.8.x) and its `/hyperframes` + `/hyperframes-cli` skills, GSAP (whatever HyperFrames bundles), HTML/CSS 3D transforms, inline SVG, FFmpeg/ffprobe, Node 22+ (`node --test`).

**Spec:** `docs/superpowers/specs/2026-10-24-booth-demo-video-design.md`. Approved keyframes: `docs/mockups/booth-demo/keyframes.html` (open it in a browser; every beat's layout and look comes from it).

## Global Constraints

- Work in the worktree `.claude/worktrees/booth-demo-video` on branch `design/booth-demo-video` (from `dev`). Do not touch `ios/`, `studio/` or `contracts/`.
- Output: `docs/mockups/booth-demo/roamory-how-it-works.mp4`, 1920 × 1080, 30 fps, H.264, no audio stream, 30–36 s.
- Palette (from `ios/Roamory/Roamory/Onboarding/OnboardingStyle.swift`): bg `#0b0b10`, accent `#03fc73` → `#8dffbe`, accent ink `#02200f`, card `#1a1a22`, chip `#22222c`, secondary text `#8e8e99`, recording red `#ff3b30`, Roamy lens bump `#01a84c`. No orange.
- Headlines: Nunito 900 (OFL, loaded by `@font-face` from `assets/fonts/`; never a Google Fonts URL), at least 72 px, fully animated in by beat start + 1.2 s and held at least 1.5 s.
- Show only what the `dev` app does: no moment detection, no adaptive frame rate, no "End trip". Saving is press to start, press again to stop.
- No Apple logo or other company branding; the phone and laptop are generic shapes built in HTML/CSS.
- HyperFrames rules: everything visible is a function of timeline time. No CSS `@keyframes`/`animation`, no `Date.now()`, no unseeded `Math.random()`, no network fetches, no timers, no `repeat: -1`. Follow the `/hyperframes` skill's "never do" list.
- Commits: no Claude attribution of any kind (no `Co-Authored-By`, no "Generated with"). English only. Commit as the repo's configured user.
- The MP4 is committed only if it is under 25 MB; otherwise commit the source and say where the MP4 is in the PR.

## Beats (source of truth for `assets/beats.js`)

| id | start | end | headline | sub | Roamy mood |
|---|---|---|---|---|---|
| `hook` | 0 | 4 | Put the phone away. | Roamory films your trip for you. | wave |
| `setup` | 4 | 10 | Tell it about your trip. | Style · where · who's coming · how long | happy |
| `start` | 10 | 15 | Clip it on. The screen goes dark. | It keeps filming quietly, easy on the battery. | sleepy |
| `buffer` | 15 | 20 | It always holds the last 45 seconds. | Old footage rolls off. Nothing fills up. | sleepy |
| `save` | 20 | 25 | Something happens? Press. Press again. It's saved. | Volume key, shutter remote or AirPods | excited |
| `studio` | 25 | 30 | One highlight video, cut by Claude on your Mac. | (none) | happy |

The executor may stretch beats (total ≤ 36 s) if a snapshot shows something unreadable; change the table in `beats.js` only, and the test keeps the rules.

## Review Focus

1. **Loop seam:** on repeat, the last frame must match the first so the jump is invisible. `verify.sh` checks SSIM(first, last) ≥ 0.97 (Task 1 writes it, Task 4 makes it pass with real content).
2. **Headlines too brief or too small to read from a booth:** `beats.test.mjs` asserts hold ≥ 1.5 s and size ≥ 72 px (Task 1).
3. **Fonts silently falling back at render** (headless Chrome has no Nunito, and network fetches are banned): `lint-rules.sh` fails on any `fonts.googleapis` URL and on a missing `assets/fonts/Nunito-*.woff2` (Task 1).
4. **Motion that the renderer doesn't capture** (the draft keyframes used CSS `@keyframes` for float and pulse): `lint-rules.sh` fails on `@keyframes`, `animation:`, `Math.random`, `Date.now`, `repeat: -1` (Task 1).
5. **Footage that is missing, unlicensed or bloats the repo:** `lint-rules.sh` fails if any file in `assets/footage/` is not listed in `CREDITS.md` or is over 3 MB (Task 3).

---

### Task 1: Tooling, project scaffold, checks, and the persistent stage

**Files:**
- Create: `docs/mockups/booth-demo/` HyperFrames project via `npx hyperframes init` (keep `keyframes.html` where it is)
- Create: `docs/mockups/booth-demo/assets/beats.js`
- Create: `docs/mockups/booth-demo/assets/roamy.svg.html` or inline in `index.html` (executor's choice) for Roamy's symbol
- Create: `docs/mockups/booth-demo/assets/fonts/Nunito-Black.woff2`, `Nunito-Bold.woff2`
- Create: `docs/mockups/booth-demo/scripts/beats.test.mjs`, `scripts/lint-rules.sh`, `scripts/verify.sh`
- Create: `docs/mockups/booth-demo/README.md`
- Modify: `docs/mockups/booth-demo/index.html` (root composition)

**Interfaces:**
- Produces: `window.ROAMORY_BEATS` (and `module.exports` of the same array): `[{ id, start, end, headline, sub, mood }]`, plus constants `HEADLINE_IN = 1.2`, `HEADLINE_OUT = 0.3`, `HEADLINE_PX = 80`.
- Produces in `index.html`: element ids `#glow`, `#phone` (3D shell, with `#screen` as the content box inside it), `#roamy` (with child groups `#roamy-wave`, `#roamy-happy`, `#roamy-sleepy`, `#roamy-excited`, one visible at a time), `#headline` and `#sub`; a master timeline registered as `window.__timelines["booth"]`; helper `setMood(tl, mood, at)` and `showHeadline(tl, beat)` defined in a root script that later tasks call.
- Produces scripts: `scripts/verify.sh <mp4>` exits 0 only if the file is 1920×1080, 30/1 fps, h264, no audio stream, duration 30–36 s, SSIM(first frame, last frame) ≥ 0.97; prints the file size and warns (no failure) over 25 MB. `scripts/lint-rules.sh` exits non-zero on the patterns in Review Focus 3–5.

- [ ] **Step 1: Install tooling**

Run: `brew install ffmpeg && npx -y hyperframes skills update && npx hyperframes browser ensure`
Expected: `ffmpeg -version` and `ffprobe -version` print; the `/hyperframes` and `/hyperframes-cli` skills are installed (load them now and follow them for every authoring step); Chrome is ready.

- [ ] **Step 2: Scaffold the project**

Run in the worktree: `npx hyperframes init docs/mockups/booth-demo` (if it refuses a non-empty folder, move `keyframes.html` aside, init, and move it back). Set the root to `data-composition-id="booth"`, `data-width="1920"`, `data-height="1080"`, `data-duration="30"`.

- [ ] **Step 3: Write the failing tests**

`scripts/beats.test.mjs` (`node --test`), loading `assets/beats.js` with `createRequire`:

```js
test('beats tile 0..total with no gaps', () => { /* beats[0].start === 0; each start === previous end */ });
test('total length is 30–36 s', () => { /* last.end >= 30 && last.end <= 36 */ });
test('ids and moods are the plan table', () => {
  assert.deepEqual(beats.map(b => b.id), ['hook','setup','start','buffer','save','studio']);
  assert.deepEqual(beats.map(b => b.mood), ['wave','happy','sleepy','sleepy','excited','happy']);
});
test('every headline holds at least 1.5 s', () => {
  for (const b of beats) assert.ok((b.end - HEADLINE_OUT) - (b.start + HEADLINE_IN) >= 1.5, b.id);
});
test('headline size is at least 72 px', () => assert.ok(HEADLINE_PX >= 72));
test('save beat says press twice', () => assert.match(beats[4].headline, /Press\..*Press again/));
```

`lint-rules.sh` and `verify.sh` as in Interfaces.

- [ ] **Step 4: Run them to see them fail**

Run: `node --test docs/mockups/booth-demo/scripts/ && bash docs/mockups/booth-demo/scripts/lint-rules.sh`
Expected: FAIL (`beats.js` missing; fonts missing).

- [ ] **Step 5: Implement `assets/beats.js`, the fonts, and the persistent stage in `index.html`**

Beats from the table above. Fonts: Nunito Black and Bold woff2 from the OFL Google Fonts repo (download once, commit the files, add the OFL line to `CREDITS.md`). Stage, matching `keyframes.html`: `#glow` radial green glow on `#0b0b10`; `#phone` a CSS-3D generic phone (rounded body, visible side edge, Dynamic Island, screen inset) whose idle float is a GSAP tween on the master timeline (yoyo with a finite repeat count that spans the loop, ending where it started); `#roamy` an inline SVG rebuilt from `ios/Roamory/Roamory/Ask/RoamyMascot.swift` with the four mood faces, a GSAP bob and a blink every ~3 s at fixed times; `showHeadline` splits the headline into words and staggers them in over `HEADLINE_IN`, out over `HEADLINE_OUT`. For this task, call `showHeadline` and `setMood` for all six beats over an empty screen so the whole 30 s has the right words and moods.

- [ ] **Step 6: Run checks, a snapshot and a draft render**

Run: `node --test docs/mockups/booth-demo/scripts/ && bash docs/mockups/booth-demo/scripts/lint-rules.sh && (cd docs/mockups/booth-demo && npx hyperframes check --json && npx hyperframes snapshot --at 2,12,22 && npx hyperframes render --quality draft --output roamory-how-it-works.mp4) && bash docs/mockups/booth-demo/scripts/verify.sh docs/mockups/booth-demo/roamory-how-it-works.mp4`
Expected: tests and lint pass; `check` has no errors; read the three snapshot PNGs and confirm the headline is in Nunito, Roamy shows wave / sleepy / excited; `verify.sh` passes (the seam passes because the stage returns to its start pose).

- [ ] **Step 7: Write `README.md` and commit**

README: what this is, the commands from Step 6, and "edit beat timings only in `assets/beats.js`". Add `.hyperframes/` to a `.gitignore` in the project folder. Don't commit the draft MP4.

```bash
git add docs/mockups/booth-demo
git commit -m "Booth video: HyperFrames project, persistent stage, beat data and checks"
```

### Task 2: Beats 1–3: hook, setup montage, start

**Files:**
- Modify: `docs/mockups/booth-demo/index.html` (or a scene file under `compositions/` if the `/hyperframes` skill prefers it; the persistent ids from Task 1 stay in the root)
- Create: `docs/mockups/booth-demo/assets/screens.css` for the rebuilt app screens

**Interfaces:**
- Consumes: `#screen`, `#phone`, `setMood`, `showHeadline`, `window.ROAMORY_BEATS` from Task 1.
- Produces: screen elements `#scr-welcome`, `#scr-style`, `#scr-globe`, `#scr-trip`, `#scr-days`, `#scr-level`, `#scr-curtain` inside `#screen`, each a `.clip` timed to its beat. `#scr-curtain` stays on through beats 4–5 (Task 3 relies on it).

- [ ] **Step 1: Build the screens from the app source, with its exact copy**

Copy and layout from the spec's screen table: welcome ("Welcome to Roamory", "Roamory films your trip so you can put the phone away and actually enjoy it.", green badge circle); style picker ("1 OF 5 · YOUR STYLE", "Which one feels like your trip?", Reels/fast cuts, Cinematic/slow, wide, Documentary/calm, captions, Vlog; Cinematic gets selected with the green outline; "Continue"); globe ("Where to?", spins to Asia then a Kyoto pin); trip deck ("Who's coming along?", Honeymoon card swipes away to Friends); days ("How many days?", count rolls to 4); level (camera preview footage or gradient with the bubble sliding to center and turning green); curtain (red dot "Recording", "Screen at 0% brightness", "Tap and hold to wake", "Shutter remote, volume key or AirPods: press to start or stop saving").

- [ ] **Step 2: Animate beats 1–3 on the master timeline**

Hook: phone floats in from the right, Roamy waves. Setup: the camera pushes in on `#phone` (scale/translateZ), the four setup screens cut on the beat (~1.4 s each) with their own micro-motion (card select, globe spin, swipe, count). Start: pull back, phone turns to face forward as on a chest mount (a simple strap shape across it), level settles, screen fades to `#scr-curtain`, Roamy goes sleepy.

- [ ] **Step 3: Check against the keyframes**

Run: `cd docs/mockups/booth-demo && npx hyperframes check --json && npx hyperframes snapshot --at 2,5,6.5,8,9.5,12,14.5 && bash scripts/lint-rules.sh`
Expected: no `check` errors. Read each PNG next to `keyframes.html` beats 1–3: the copy above is legible on the phone, the headline is never covered by the phone, nothing is orange.

- [ ] **Step 4: Commit**

```bash
git add docs/mockups/booth-demo
git commit -m "Booth video: hook, setup montage and start beats"
```

### Task 3: Beats 4–5: rolling buffer and save

**Files:**
- Modify: `docs/mockups/booth-demo/index.html` (or its scene file)
- Create: `docs/mockups/booth-demo/assets/footage/` (4–8 travel clips or stills), `docs/mockups/booth-demo/CREDITS.md` entries
- Modify: `docs/mockups/booth-demo/scripts/lint-rules.sh` (footage rules)

**Interfaces:**
- Consumes: `#scr-curtain`, `#phone`, `setMood`, `showHeadline` from Tasks 1–2.
- Produces: `#strip` (the film strip, frames `.frame`), `#bracket`, `#press-volume`, `#press-remote`, `#press-airpods`, `#scr-saving` ("Stop saving" pill with a running timer), `#gallery-tile`. Task 4 reuses `#strip` frames as the clips that fly to the laptop.

- [ ] **Step 1: Add the failing footage rule**

In `lint-rules.sh`: every file in `assets/footage/` appears by name in `CREDITS.md` with its source URL and license, and is ≤ 3 MB.

Run: `bash docs/mockups/booth-demo/scripts/lint-rules.sh` after adding one uncredited test file; Expected: FAIL naming it. Remove the test file.

- [ ] **Step 2: Source the footage**

Freely licensed travel clips or stills (Pexels or similar), or Daniel's own recordings if he supplies them. Never the FFmpeg placeholders in `ios/RoamoryKit/.../SampleClips/`. Download each into its own new folder in the scratchpad, then transcode into `assets/footage/` with FFmpeg: ≤ 4 s, 640 px wide, no audio, H.264 (or JPEG stills). Credit each in `CREDITS.md`.

- [ ] **Step 3: Animate beat 4 (buffer)**

Phone small and dark on the right with the red "Recording" dot. `#strip` flows right-to-left past it like a conveyor (a seamless translate driven by the timeline, footage frames inside); `#bracket` labeled "last 45 s" stays fixed over the newest frames; frames leaving the bracket fade to ~0.1 opacity off the left.

- [ ] **Step 4: Animate beat 5 (save), two presses**

Press 1: the three press icons pulse together (ring scale + fade); the frames in the bracket light green (border + glow) and the bracket's right edge keeps extending as new frames arrive; `#scr-saving` shows "Stop saving" with a timer counting 0:01 → 0:03 driven by the timeline. Press 2: icons pulse again; the lit frames lift, shrink and fly into `#gallery-tile` (a Photos-style tile near the phone). Roamy excited.

- [ ] **Step 5: Check**

Run: `cd docs/mockups/booth-demo && bash scripts/lint-rules.sh && npx hyperframes check --json && npx hyperframes snapshot --at 16,18.5,21,22.5,24`
Expected: lint and check pass; snapshots match `keyframes.html` beats 4–5; "last 45 s" and "Stop saving" are legible; there are visibly two separate presses.

- [ ] **Step 6: Commit**

```bash
git add docs/mockups/booth-demo
git commit -m "Booth video: rolling buffer and two-press save beats, licensed footage"
```

### Task 4: Beat 6 (Studio), loop closure, delivery render, PR

**Files:**
- Modify: `docs/mockups/booth-demo/index.html` (or its scene file)
- Modify: `docs/mockups/booth-demo/README.md`
- Create: `docs/mockups/booth-demo/roamory-how-it-works.mp4`

**Interfaces:**
- Consumes: everything above.
- Produces: `#laptop` (generic laptop, `#terminal` inside it), `#scr-make` (the phone's Make video progress line with a sparkle wand icon), `#scr-gallery` (Gallery with the finished video tile).

- [ ] **Step 1: Animate beat 6**

Lit clips from beat 5 fly in an arc from the phone into `#laptop`. `#terminal` types lines on the timeline: `$ python -m studio.server`, `Roamory Studio pairing code: 4821`, `Received 6 clips`, Claude Code progress lines, `✓ Done`. Meanwhile `#scr-make` shows the stage text and a timer. Then the phone shows `#scr-gallery` with the video tile playing a few footage frames. Roamy happy.

- [ ] **Step 2: Close the loop**

From about 28.8 s, everything eases back to the exact state at t = 0: laptop, strip and gallery gone; phone, Roamy, glow and headline layer in their frame-0 pose and opacity. Run `bash scripts/verify.sh` on a draft render; Expected: SSIM(first, last) ≥ 0.97. If it fails, compare the snapshots at 0 and 29.96 and fix whatever differs.

- [ ] **Step 3: Full checks and delivery render**

Run: `cd docs/mockups/booth-demo && node --test scripts/ && bash scripts/lint-rules.sh && npx hyperframes check --json && npx hyperframes snapshot --at 26,27.5,29.9 && npx hyperframes render --quality delivery --output roamory-how-it-works.mp4 && bash scripts/verify.sh roamory-how-it-works.mp4`
Expected: all pass; verify prints the size.

- [ ] **Step 4: Watch it looped**

Run: `ffplay -loop 0 -fs docs/mockups/booth-demo/roamory-how-it-works.mp4` (or open in QuickTime with View > Loop). Watch three loops: no jump at the seam, every headline readable before it leaves. Then ask Daniel to watch and approve it; apply his notes before the PR.

- [ ] **Step 5: Commit and open the PR to `dev`**

Commit the MP4 only if `verify.sh` reported under 25 MB. Update the README with the final commands. Push the branch and open a PR to `dev` (never `main`) titled "Booth demo video: how Roamory works loop". The body says what it is, how to render and preview it, that motion graphics are Andrew's area (Daniel has told him), and that beat 3 assumes the dark recording screen is back on for the booth. No Claude attribution lines.

```bash
git add docs/mockups/booth-demo
git commit -m "Booth video: Studio beat, seamless loop and delivery render"
git push -u origin design/booth-demo-video
gh pr create --base dev --title "Booth demo video: how Roamory works loop" --body-file /path/to/body.md
```
