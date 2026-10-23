# Decisions log

Short record of team decisions. Newest first. Format: date, decision, why.

- 2026-10-22: The demo's final video is made from pre-recorded footage, replayed through the app (TRD §12.4). Why: a real walk cannot happen on stage.
- 2026-10-22: The phone is worn in a regular chest mount, camera facing forward; its clamp rotates, so the style sets portrait or landscape (PRD FR-007a). Why: a pocket films nothing, an off-the-shelf mount means no custom hardware, and matching orientation avoids cropping.
- 2026-10-22: Moment selection runs in the cloud on a frontier model API, behind our own backend. Why: best selection quality, and the API key stays off the phone.
- 2026-10-22: Footage goes into a rolling FIFO buffer on the phone; selected moments are protected from deletion. Why: lets us keep the seconds before a moment, and unselected footage never piles up.
- 2026-10-22: The frame rate drops when nothing important is happening (adaptive frame rate). Why: battery and heat.
- 2026-10-22: Pivot from camera glasses + Raspberry Pi to an iPhone app plus a Bluetooth button. The glasses design is discarded. Why: no custom hardware to build or debug.

## Open

- Which VLM provider/model IDs and per-trip spend cap (TRD §14)
- Who owns each folder (fill in README)
- The proposals added in the docs review PR: trips with pause and resume (FR-007b), button moments beating the length target (FR-009), and how replay mode works (TRD §12.4)
