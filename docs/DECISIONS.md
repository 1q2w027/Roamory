# Decisions log

Short record of team decisions. Newest first. Format: date, decision, why.

- 2026-10-23: The rolling buffer is an in-memory ring buffer of encoded (HEVC) samples; a moment is written to disk only when kept, by passthrough (TRD §5). Replaces 2-second segment files on disk. Why: unselected footage never touches storage, and there is no segment index or cleanup to maintain.
- 2026-10-23: Remotion cloud render as an optional engine; trimmed selected clips are uploaded, deleted after download; AVFoundation remains default and fallback (TRD §9.2, §11.3; plan in `docs/remotion-plan.md`). Why: richer motion graphics (kinetic titles, lower thirds, animated transitions) than Core Animation gives us, without risking the video: any cloud failure still renders on the phone.
- 2026-10-22: The demo's final video is made from pre-recorded footage, replayed through the app (TRD §12.4). Why: a real walk cannot happen on stage.
- 2026-10-22: The phone is worn in a regular chest mount, camera facing forward (PRD FR-007a). Why: a pocket films nothing, and an off-the-shelf mount means no custom hardware.
- 2026-10-22: Moment selection runs in the cloud on a frontier model API, behind our own backend. Why: best selection quality, and the API key stays off the phone.
- 2026-10-22: Footage goes into a rolling FIFO buffer on the phone; selected moments are protected from deletion. Why: lets us keep the seconds before a moment, and unselected footage never piles up.
- 2026-10-22: The frame rate drops when nothing important is happening (adaptive frame rate). Why: battery and heat.
- 2026-10-22: Pivot from camera glasses + Raspberry Pi to an iPhone app plus a Bluetooth button. The glasses design is discarded. Why: no custom hardware to build or debug.

## Open

- Which VLM provider/model IDs and per-trip spend cap (TRD §14)
- Who owns each folder (fill in README)
- The proposals added in the docs review PR: capture orientation set by style (PRD FR-007a), trips with pause and resume (FR-007b), button moments beating the length target (FR-009), and how replay mode works (TRD §12.4)
- Does our chest mount's clamp rotate to both orientations?
- Where the Remotion render service is hosted, and whether we need a Remotion company license (TRD §14)
