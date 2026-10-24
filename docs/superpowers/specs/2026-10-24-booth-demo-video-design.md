# Booth demo video: how Roamory works

## Intent

A short motion graphic that loops on a screen at our hackathon booth. People walk past and glance at it, usually with no sound. It has one job: show how the app works, from setup to the finished highlight video. Brand and story videos come later as separate pieces; this one is only the "how it works" loop.

It should feel like a product launch film, not a slideshow. The first storyboard (flat icons and boxes in order) was rejected as too simple. The direction that was agreed: a 3D iPhone moving through space with the real app screens on it, big animated headlines, camera moves into the screen between beats, and Roamy the mascot actually moving.

## Goals

- Someone who watches one loop understands the flow: set up a trip, clip the phone on, it films with the screen dark and always holds the last 45 s, a press saves that moment, and Roamory Studio on a Mac turns the saved clips into one video.
- Each beat makes sense with no sound and in a few seconds, readable from a few metres away.
- The loop is seamless: the last frame leads into the first with no visible cut.
- The phone screens look like the latest app (`ios/mount-level` branch, which includes the bubble level and the landscape layout).

## Non-goals

- Brand, story or emotional pieces (those come later).
- Ask (the Roamy chat), Evaluate, the debug settings and the "Make on this iPhone" backup render.
- Sound or music.
- Any change to the app itself.

## Anti-goals (a failure even if it plays)

- It looks like a slideshow: static screens that cut from one to the next.
- It shows features the hackathon app does not have. Moment detection, adaptive frame rate and "End trip" are in the PRD and on `main`, but not in the `dev` app. The Roamory video shows only what `dev` does.
- It uses the old orange palette from `docs/mockups/iphone-screens.png`. The app is now green.
- Text too small or on screen too briefly to read from a booth.
- An Apple logo, Apple's product imagery or another company's branding. The phone is a generic modern iPhone shape (rounded body, Dynamic Island) and the Mac a generic laptop shape, both built by us.

## Format (Claude's call; the user said "just loop it")

- 1920 × 1080, landscape, 30 fps, MP4 (H.264), silent.
- About 30 s per loop. The builder may stretch it to 36 s if a beat needs room to read; no longer.

## Look

- **Palette from the app** (`ios/Roamory/Roamory/Onboarding/OnboardingStyle.swift`, `Theme`): background `#0b0b10`, accent `#03fc73` → `#8dffbe` gradient, ink on the accent `#02200f`, cards `#1a1a22`, chips `#22222c`, secondary text `#8e8e99`, recording red `#ff3b30`. Soft green glow behind the phone, like the intro's "breathing green light".
- **Type:** SF Pro Rounded look (the app uses `.rounded` with heavy titles). Use a rounded web font that is close, such as Nunito or SF Pro Rounded if it is available locally. Headlines are large (around 72–96 px at 1080p) and animate in word by word, beside the phone.
- **The phone:** a 3D iPhone body built in HTML/CSS 3D (or three.js if CSS isn't enough). It floats, tilts and turns between beats. The camera pushes into its screen to show detail and pulls back out to change beats.
- **Roamy:** the round green camera with a face from `ios/Roamory/Roamory/Ask/RoamyMascot.swift` (lens bump on top, rounded body, eyes; it bobs, blinks, and has wave, sleepy, excited and happy moods). Rebuild it in SVG/HTML from that file. Roamy hosts the video: it waves at the start, looks sleepy or calm while the screen is dark, gets excited at the save, and is happy at the end.

## Screens: rebuilt, not recorded (user's decision)

Every phone screen is rebuilt in HTML from the app's source, using its exact copy, colors and layout, so it stays sharp and each element can animate on its own. Sources:

| Screen | Source in `ios/Roamory/Roamory/` | Copy to use |
|---|---|---|
| Style picker | `Onboarding/StylePickerStep.swift` | "1 OF 5 · YOUR STYLE", "Which one feels like your trip?", cards Reels (fast cuts), Cinematic (slow, wide), Documentary (calm, captions), Vlog |
| Destination globe | `Onboarding/DestinationStep.swift`, `GlobeView.swift` | "Where to?", a continent then a city |
| Trip type deck | `Onboarding/TripTypeStep.swift` | "Who's coming along?", cards from `ios/RoamoryKit/Sources/RoamoryKit/Resources/onboarding_catalog.json` (Honeymoon, Friends, Family, Solo, School trip, Business) |
| Trip length | `Onboarding/TripLengthStep.swift` | "How many days?" |
| Recording + level | `Recording/RecordingView.swift`, `LevelOverlay.swift` | the camera preview with the bubble level settling to center |
| Dark screen | `Recording/RecordingCurtain.swift` | red dot "Recording", "Screen at 0% brightness", "Tap and hold to wake", "Shutter remote, volume key or AirPods: press to start or stop saving" |
| Make video (Studio) | `Studio/StudioSheet.swift` | "Looking for Roamory Studio on this Wi-Fi…", the Mac row, the progress line with "wand.and.sparkles" |
| Gallery | `Gallery/GalleryView.swift` | the finished video tile |

Footage inside the phone (the camera preview and the film strip) is travel footage or stills. The clips in `ios/RoamoryKit/Sources/RoamoryKit/Resources/SampleClips/` are synthetic FFmpeg placeholders, not travel footage, so don't use them. Use freely licensed travel clips or stills (for example from Pexels, with the license noted in `docs/mockups/booth-demo/CREDITS.md`), or the team's own recordings if Daniel supplies them (Claude's call).

## Beats

Times are a guide for a 30 s loop. Each beat has one headline. The headline copy is a draft; the builder may tighten it but must keep the meaning.

1. **0–4 s · Hook.** Roamy pops in and waves next to the floating phone. Headline: "Put the phone away." Sub: "Roamory films your trip for you."
2. **4–10 s · Set up.** The camera pushes into the phone and a fast montage plays through four setup steps: a style card is chosen, the globe spins to a city, a trip card is swiped, the days are set. Headline: "Tell it about your trip."
3. **10–15 s · Start.** The phone turns to show it clipped on a chest mount, facing forward. On screen, the bubble level slides to center and turns green, then the screen fades to black with the small red "Recording" dot. Roamy goes calm or sleepy. Headline: "Clip it on. The screen goes dark."
4. **15–20 s · Rolling buffer (the key idea).** A glowing film strip of travel footage wraps around or flows past the phone like a conveyor. A bracket marks "last 45 s"; the oldest frames fade off the end. Headline: "It always holds the last 45 seconds."
5. **20–25 s · Save.** In the app a press does not save in one go: the first press (volume key, shutter remote, AirPods stem or the Save buffer button) starts saving the buffer plus what follows, the button becomes "Stop saving" with a running timer, and a second press stops it (`Recording/RecordingView.swift`). Show it that way, compressed (Claude's call): press 1 pulses, the strip inside the bracket lights green and keeps growing while a short "saving" timer runs, press 2 pulses, and the lit clip flies into a Photos/Gallery tile. The three press devices can appear as small icons around the phone rather than three separate shots. Roamy gets excited. Headline: "Something happens? Press. Press again. It's saved."
6. **25–30 s · Studio.** Saved clips fly over Wi-Fi from the phone to a laptop. Roamory Studio has no Mac app; it runs in a terminal (`studio/server.py`), so the laptop shows a stylized terminal window (Claude's call), not an invented UI: "Roamory Studio pairing code: 4821", then Claude Code's progress lines ending in "Done". The phone shows the matching Make video progress line with the `wand.and.sparkles` icon. A finished highlight video plays back on the phone in the Gallery. Roamy is happy. Headline: "One highlight video, cut by Claude on your Mac." The last frames ease back to beat 1's opening position so the loop has no cut.

## How it gets made (Claude's calls)

- **HyperFrames, local kit.** The user asked for HyperFrames. HeyGen's hosted HyperFrames tools refuse to compose or render from Claude Code, so we use the local kit: `npx skills add heygen-com/hyperframes`, then its skills (`/hyperframes` to compose, `/hyperframes-cli` to lint, preview and render). The result is an HTML/GSAP composition in the repo that renders to MP4 on this Mac.
- **Tooling to install:** the HyperFrames skills, and `ffmpeg` (`brew install ffmpeg`), which is not on this Mac yet. Install only what the kit's own instructions need.
- **Where it lives:** `docs/mockups/booth-demo/`, which holds the composition source, any assets it uses, and the rendered `roamory-how-it-works.mp4`. CLAUDE.md says motion graphics are Andrew's area and design assets go in `docs/mockups/`; Daniel will let him know.
- **Git:** a new branch `design/booth-demo-video` from `dev`, a small PR to `dev`. No Claude attribution in commits or PRs. Commit the MP4 if it is under 25 MB; otherwise commit the source and say in the PR where the MP4 is.

## Done means

- `docs/mockups/booth-demo/roamory-how-it-works.mp4` exists: 1920 × 1080, 30 fps, silent, 30–36 s.
- Played on repeat, there is no visible jump at the loop point.
- Every headline can be read on a 1080p screen viewed from about 3 m, and stays on screen for at least 1.5 s after it finishes animating in.
- Daniel has watched it and approved it.

## Assumptions

- The dark recording screen (`RecordingView.curtainEnabled`, switched off "for debugging" in `eb2b736`) will be back on for the booth, so beat 3 shows the screen going dark. If it stays off, beat 3 changes to the lit camera view with the level.
- Draft keyframes Daniel approved: `.superpowers/brainstorm/96045-1792882995/content/storyboard-v2.html` (local only, not committed). The build follows their layout and look.

## Left to the builder

- Exact easing, camera paths, the 3D technique (CSS 3D or three.js) and timings within each beat.
- How the setup montage is cut, and how much of each screen shows.
- The exact headline wording, within the meaning above.
- The footage used inside the phone and on the film strip.
