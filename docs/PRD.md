# Product Requirements Document (PRD)

## 1. Product Overview

**Working Name:** Roamory (AI Travel Videographer)
**Version:** 2.0 — iPhone pivot
**Platform:** iPhone app (camera, on-device UI) + AI processing
**Status:** Draft. Replaces v1.0 (camera glasses + Raspberry Pi), which is discarded entirely.

> **How to read this document.** Items marked **(Decided)** came directly from the product owner. Items marked **(Proposed)** are the author's guesses to be confirmed or changed. Section 12 lists what is still open.

### 1.1 Product Summary

Roamory is an iPhone app that films a trip for the user and turns it into a finished video.

The user first tells the app what kind of video they like, where they are going, what kind of trip it is and how long it will take. The app learns these preferences and keeps them. When the user taps Start Recording, the iPhone camera films the trip. The screen goes dark to save battery, and the camera lowers its frame rate when nothing important is happening, like an iPhone's ProMotion display. A Bluetooth button lets the user force a moment into the final video. After the trip, the app processes the footage into a final video, and the user reviews it in the app.

### 1.2 Problem Statement

1. **Filming interrupts the experience.** Travelers take their phones out to capture moments instead of enjoying them.
2. **Editing takes effort.** Travelers collect footage but rarely turn it into a finished video.
3. **Generic results.** A honeymoon, a school trip and a friends' trip should not produce the same video.

### 1.3 Product Vision

*Live the moment. Let AI capture the memory.*

### 1.4 Differentiators

- An interactive, animated setup that learns the user's taste instead of showing a form.
- Video style and trip type shape what gets filmed and how the video is cut.
- Battery-aware capture: dark screen while recording, and an adaptive frame rate that drops when nothing is happening.
- A Bluetooth button that guarantees an important moment is kept.
- No hardware beyond the user's iPhone.

---

## 2. Target Users and Use Cases

### 2.1 Primary Users (Proposed)

- **Casual travelers** who want a good trip video without filming or editing.
- **Couples, families and friend groups** on a specific kind of trip (honeymoon, family, friends, school).

### 2.2 Primary Use Case

1. A first-time user opens the app and picks the video style that fits them from four sample clips.
2. They choose a destination on an interactive map: continent, then country, then city.
3. They say what kind of trip it is and how long it will last.
4. They tap Start Recording and wear the phone with the camera facing forward, in a regular chest mount (Section 5.1a). A phone in a pocket cannot film.
5. During the trip, the app films scenes its model finds worth keeping. When the user presses the Bluetooth button, that moment is kept no matter what.
6. When the trip ends, the app produces a video. The user watches and reviews it in the app.

---

## 3. Goals and Success Metrics

### 3.1 MVP Goals

- **Goal A — Personalized setup.** A new user completes style, destination, trip type and trip length through an interactive flow, and the choices are saved.
- **Goal B — Battery-aware capture.** The app records from the iPhone camera with the screen at zero brightness. Lowering the camera frame rate between interesting scenes is P1: if the battery spike (Section 12, question 7) shows mid-session rate changes are unsafe, the MVP records at a fixed rate.
- **Goal C — Guaranteed moments.** A Bluetooth button press always puts that scene into the final video.
- **Goal D — Finished video.** The app turns captured footage into a playable video, which the user can review in the app.

### 3.2 Success Metrics (Proposed, to be tuned)

| Metric | MVP target |
|---|---|
| Setup | A new user reaches Start Recording in under 2 minutes |
| Style choice | Saved and applied to the final video |
| Recording | Camera films with screen at 0% brightness |
| Adaptive frame rate (P1) | Battery drain lower than constant full-rate recording (measured) |
| Bluetooth button | 100% of presses end up in the final video |
| Detection | At least 2–3 correctly detected moments in a scripted demo |
| Personalization | Different style or trip type visibly changes the output |
| Final output | Playable video of 30–60 seconds |

These are engineering targets, not guaranteed benchmarks.

### 3.3 Non-Goals

- Any hardware other than the iPhone and a Bluetooth button.
- All-day battery life guarantees.
- Guaranteed detection of every meaningful moment.
- Manual timeline editing.
- Multi-user collaboration.
- Android.
- Recording while the app is in the background (iOS does not allow camera capture there; see Section 9).

---

## 4. Onboarding and Trip Setup

All steps use animation and direct manipulation. None is a plain list of buttons.

### 4.1 Video Style Picker (Decided)

**FR-001.** On first launch, the app shows four sample video clips side by side on one screen, one per style. Candidate styles: Reels, Cinematic (movie), Documentary, Vlog.

- The user picks the one that fits best.
- The choice is stored as part of the user's **personal preference data** and reused for later trips.
- (Proposed) Clips loop silently; tapping one expands it with sound while the others fade.

### 4.2 Destination (Decided)

**FR-002.** The user selects a destination as continent, then country, then city, using an interactive map visualization with animation.

- (Proposed) A globe spins; tapping a continent zooms into it; countries highlight under the finger; city pins appear and pulse when selected.

### 4.3 Trip Type (Decided, interaction Proposed)

**FR-003.** The user selects the kind of trip: honeymoon, family, friends, school, and similar. The interaction must be animated and not a plain button row.

Interaction ideas under consideration (author's proposals):

- **Companion cards:** swipe through illustrated cards. Leading idea.
- **Drag your people:** drop avatars onto a scene; the trip type is inferred.
- **Vibe sliders:** drag between poles such as calm and adventurous.
- **Short AI chat:** natural-language questions about who is coming and why.

### 4.4 Trip Length (Decided)

**FR-004.** The user says how long the trip will take, asked during setup before recording starts. It is used to pace the app (for example, how selective to be) and to size the final video. How exactly it is used is open (Section 12).

### 4.5 Start Recording (Decided)

**FR-005.** After setup, a Start Recording button begins the session.

### 4.5a Permissions and Consent (Proposed)

**FR-005a.** Before the first recording, the app asks for what it needs, each with a one-line reason: camera (required), motion (for frame-rate ramp-up), notifications (to say recording stopped), and adding to Photos (when the user saves the video). Microphone and location are asked only if the user turns on audio or landmark detection. A consent screen explains what leaves the phone (small still frames during the trip; the kept clips when the trip ends, uploaded to make the video and then deleted) and sets the "Allow cloud analysis" setting. Denying camera blocks recording with a clear explanation; denying anything else turns that feature off.

### 4.6 Personal Preference Data (Decided)

**FR-006.** The app stores the user's style choice and may store trip-type and destination history. Stored preferences prefill future trips and inform moment selection and editing.

---

## 5. Recording

### 5.1 Recording Session (Decided)

**FR-007.** While a trip is active:

- The app uses the iPhone camera to film.
- The screen brightness is set to 0 to save battery.
- The user can wake the screen to see status and stop the trip.

### 5.1a Wearing the Phone (Decided: chest mount; orientation rule Proposed)

**FR-007a.** The phone is worn with the back camera facing forward, in a regular chest mount (Decided). No custom hardware. Onboarding shows how to wear it. The video style sets the orientation so the final video needs no crop: portrait for Reels (9:16), landscape for Cinematic, Documentary and Vlog (16:9). The app checks the orientation from motion sensors at Start Recording and while recording, and asks the user to fix it (with a haptic) if it is wrong.

### 5.1b Trips and Recording Sessions (Proposed)

**FR-007b.** A trip can last days, but one recording session cannot: the app must stay open, and the battery and heat run out. So a trip is made of one or more **recording sessions**.

- The user can pause and resume a trip. A phone call, leaving the app, low battery (under 10%) or overheating also pauses it, with a notification. Resuming always takes a user action.
- Only End Trip ends the trip and starts making the video. When the trip length has passed, the app reminds the user to end it.
- Moments from all sessions go into one final video.

### 5.2 Adaptive Frame Rate (Decided concept, details Proposed)

**FR-008 (Decided).** Like an iPhone's ProMotion display, which drops from 120 Hz toward 1 Hz when nothing is moving, the app lowers the camera frame rate when nothing important is happening and raises it when something is. The goal is to save battery and heat.

- (Proposed) Several tiers, for example 30 fps, 10 fps and 2 fps.
- (Proposed) A cheap check on the phone raises the frame rate: frame difference between samples, motion sensors, or a button press. No cloud call is needed to wake up.
- (Proposed) The cloud model decides which footage is kept (Section 6), not when the frame rate changes.
- Trade-off: footage recorded before the ramp-up is low frame rate and looks like time-lapse. The following reduce this (all Proposed):
  - **Raised floor.** The lowest tier is about 10 fps, not 1–2 fps, so the footage still plays as video. The exact floor is set by battery measurements on a real iPhone (see the spike in Section 12).
  - **Early ramp-up.** Signals that come before a good moment raise the rate: the user slows or stops walking (motion sensors), the phone is raised or tilted, the user nears a landmark in the chosen city, or sound gets louder.
  - **Fast up, slow down.** The rate rises to full within about a second and stays high for roughly 20–30 seconds after the last activity, so the end of a moment is always full quality.
  - **Speed-ramp in the edit.** Any remaining low-fps lead-in is edited as a deliberate time-lapse that accelerates into normal speed at the moment, where the video style allows it.
  - **Button override.** A Bluetooth press goes straight to full frame rate, and the buffer protects the footage before the press, so a slightly late press still works.

### 5.2a Rolling Buffer (Decided)

**FR-008a (Decided).** The app takes in the video stream and holds it in a buffer for a set amount of time, then deletes it, like a queue (first in, first out).

- When a moment is selected (by the AI or the Bluetooth button), the buffered footage around it is protected from deletion and kept for the final video. This allows keeping the seconds before the moment.
- (Proposed) The buffer must be longer than the cloud decision delay plus the pre-roll, so a late decision still finds its footage. Exact length is open.
- (Proposed) The buffer is held in the phone's memory, not on disk. Unselected footage is discarded when it leaves the buffer and is never written to storage.

### 5.3 Bluetooth Button (Decided)

**FR-009.** A Bluetooth button connects to the app. When the user presses it, the current scene is guaranteed to appear in the final video, overriding the AI's selection and any budget or cooldown limits.

- (Proposed) The press also raises the camera to full frame rate and protects the buffered footage around the press.
- (Proposed) The app confirms the press with a haptic or sound, since the screen is dark.
- (Proposed) The guarantee also beats the video length target. If button moments do not fit, each is cut to the style's shortest clip length, AI moments are dropped first, and the video runs longer than the target if it has to.

### 5.4 Moment Metadata (Proposed)

**FR-010.** Each saved moment records: id, trip, start and end time, source (AI or button), category, score, a short description, and a file reference.

---

## 6. Moment Selection and AI

### 6.1 Principle

Cheap checks first; expensive models only when needed. Most of the time the app does little work, which saves battery and cost.

### 6.2 Selection Signals (Proposed)

- Visual interest and scene change.
- Match with the user's style, trip type and destination.
- Image quality (blur, exposure).
- Novelty relative to already saved moments.

### 6.3 Personalization (Proposed)

**FR-011.** Trip type, style and preferences influence which moments are chosen. For example, a honeymoon prioritizes couple and scenic moments; a school trip prioritizes group moments.

### 6.4 Where the Model Runs (Decided)

**FR-011a (Decided).** AI selection runs in the cloud, using a frontier model API.

- (Proposed) The phone uploads small sample frames, not full video, and the cloud model returns keep or skip decisions.
- (Proposed) Cheap on-phone checks reduce how many frames are sent, to limit cost and battery.
- Requires user consent (Section 10). Without a network, the app keeps recording, and button-pressed moments are still kept.

---

## 7. Video Generation

**FR-012.** After the trip, the app processes the footage into a final video without manual editing.

**FR-013.** The video follows the style picked in setup (Reels, Cinematic, Documentary, Vlog), which controls clip length, pacing, transitions, music and aspect ratio.

**FR-014.** Clips are selected, ordered (generally chronologically) and trimmed automatically. Duplicate or near-identical moments are reduced.

**FR-015.** Titles and captions may only use information the user provided (destination, trip type) or what is visible in the footage. The video must not claim events that did not happen.

**FR-016 (Proposed).** Output is MP4/H.264, 30–60 seconds for the MVP (longer only when button moments need it, FR-009), with vertical aspect for Reels and horizontal for the others, matching how the phone was worn (FR-007a).

**Where processing runs:** the video is made on a server by an AI agent (decided 2026-10-24, `docs/DECISIONS.md`).

---

## 8. Review Experience

**FR-017 (Decided).** The user can review the final video in the app.

**FR-018 (Proposed).** Review includes: playback, saving or sharing the video, and a list of the moments used, with the button-pressed ones marked.

**FR-019 (Proposed, may be P1).** The user can give feedback on the result (for example, too long, wrong style, missing a moment), which improves their saved preferences.

---

## 9. Platform and Constraints

- **iPhone app** (native iOS is assumed; the framework is not yet chosen).
- **Camera:** recording requires the app in the foreground. With brightness at 0 the screen is still on, so the app must disable auto-lock during a trip. iOS does not allow camera capture while the app is in the background.
- **Heat and battery:** continuous recording is thermally and battery costly; the adaptive frame rate exists to reduce both.
- **Bluetooth button (Proposed assumption):** a BLE button that the app can read while in the foreground with the screen dark. The model of button and how it pairs is open.
- **Storage:** footage is bounded; unselected footage is discarded.
- **Connectivity:** capture must work without a network. Anything that needs the network (cloud analysis, cloud rendering) must degrade gracefully.

---

## 10. Privacy and Safety

- Recording begins only after an explicit tap on Start Recording.
- When the screen is dark, the user must still be able to tell the app is recording (for example, the iOS camera indicator, plus an in-app indicator on wake). The product must not be a covert recorder.
- Cloud analysis or rendering requires clear user consent, with a setting to turn it off.
- Unselected footage is discarded automatically.
- Audio recording and filming identifiable bystanders may require consent depending on local law; audio can be turned off.
- Preference data stays on the user's device unless the user opts in to sync (Proposed).

---

## 11. Scope and Priorities

### P0 — Must have

| Feature | Acceptance |
|---|---|
| Style picker | Four-clip picker saves the choice |
| Destination | Interactive map: continent, country, city |
| Trip type and length | Animated selection and length input |
| Permissions and consent | Camera granted; cloud consent recorded |
| Start Recording | Begins an iPhone camera session |
| Pause and resume | A paused trip resumes into the same trip |
| Dark-screen recording | Brightness 0 during the trip |
| Rolling buffer | Stream held in a queue buffer; selected moments are protected |
| Moment selection | Cloud AI picks moments; style and trip type matter |
| Bluetooth button | Press always lands in the final video |
| Final video | Automatic playable video |
| Review | In-app playback |

### P1 — Should have

- Adaptive frame rate with tiers and an on-phone ramp-up trigger.
- Persisted preference data used across trips.
- Moment list in the review screen.
- Feedback on the result.
- Haptic confirmation for button presses.

### P2 — Future

- Natural-language re-editing.
- Manual timeline editing.
- Multi-day trip storytelling.
- Audio-aware detection.
- Sharing to social networks.

---

## 12. Open Questions

| # | Question | Notes |
|---|---|---|
| 1 | Which on-phone signal raises the frame rate, and what are the tiers? | Frame difference and motion sensors are proposed. Needs testing. |
| 2 | How long is the buffer, and how long is the pre-roll? | Must exceed cloud decision delay. |
| 3 | ~~Where is the video rendered: on the phone or on a server?~~ Decided: on a server, by an AI agent (TRD §9). | Affects processing time and consent. |
| 4 | How is trip length used? | Pacing, selectivity, video length, or all three. |
| 5 | Which trip-type interaction do we build? | Card deck is the current lead. |
| 6 | Which Bluetooth button hardware, and how does it pair? | Must work with the screen at 0 brightness. |
| 7 | What are the battery and heat costs at 30, 15, 10 and 2 fps? | Spike: a small throwaway iPhone test app that records at each rate for 10 minutes with the screen at 0 brightness, on a real device. Sets the floor in FR-008. |
| 8 | Native Swift or a cross-platform framework? | Not yet decided. |
| 9 | Sample style clips: who produces them? | Need four representative clips. |
| 10 | Final list of video styles. | Reels, Cinematic, Documentary and Vlog are proposals. |
| 11 | Hackathon schedule and team roles for the new scope. | The v1.0 36-hour plan no longer applies. |
| 12 | Does our chest mount's phone clamp hold the phone in both portrait and landscape? | Decided: a regular chest mount. Standard clamps usually rotate; check ours. If it cannot, all styles record in the one orientation it holds. |
| 13 | ~~What is the live demo?~~ | Decided: the demo's final video is made from pre-recorded footage, replayed through the app (TRD §12.4). |

---

## 13. Related Documents

- `docs/TRD.md` is rewritten for this PRD (v2.0). Its choices are proposals until confirmed.
- `contracts/` is not yet populated; its schemas should be defined next, in their own PR.
