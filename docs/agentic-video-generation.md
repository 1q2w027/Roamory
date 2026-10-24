# Plan: Agent mode for the highlight video

## Context

Today the video is made in two steps. `/v1/plan` (`backend/app/plan/service.py`) has Claude return a JSON edit spec through one strict tool call. Then the spec is executed deterministically, either by AVFoundation on the phone or by the fixed Remotion `Highlight` composition (`render/src/remotion/Highlight.tsx`). The model can only express what the spec schema allows: cut, fade or dissolve, one caption per clip, and a fixed title and end card for each style.

**Agent mode** lets an AI agent make the video end to end. It gets the trip context, the style preset and every candidate clip. It watches the clips by sampling frames, then picks and trims them, writes its own Remotion composition, renders it, checks the result and fixes problems, then submits the MP4. **Decided with the user:**
- The agent owns everything; there is no `/v1/plan` call in this mode.
- It runs on the **Claude Agent SDK (TypeScript) inside the existing `render/` service**, reusing its upload, job and polling API, Fly hosting and retention rules.

The existing pipeline is unchanged and becomes the fallback: any agent failure or timeout runs the normal plan and render, so the video always completes.

This breaks the TRD §1 rule that "the LLM only produces JSON and rendering is deterministic". It needs a decision entry and a heads-up to the team before it ships.

## Phase A0: Decision, docs, contracts (PR `contracts/agent-render`, tell the team)

- `docs/DECISIONS.md`: "Agent mode (optional): a Claude agent in the render service selects, edits and renders the video with Remotion; the deterministic plan and render pipeline is the fallback."
- `docs/TRD.md`:
  - §1: note the exception.
  - New §9.3 "Agent mode": the flow below, its limits, and that it needs "Allow cloud analysis" on.
  - §11.3: candidate clips (not only the selected ones) are uploaded, with the same retention rules.
  - §14: open questions on cost per video and time to finish.
- New `contracts/agent_request.schema.json`, the `request` part of `POST /v1/agent`:
  - `{ trip_id, style, target_s, effective_target_s, context{destination, trip_type, start_date}, clips: [...] }`;
  - each clip carries `moment_id, source, event_type, description, score, t_from_ms, duration_s, has_audio, proposed_in_s, proposed_out_s, low_fps_lead_in_s`. These are the same fields as the plan request's clip table (`contracts/plan_request.schema.json`), so reuse its `$defs` if it has them.
- New `contracts/agent_result.schema.json`, returned by `GET /v1/agent/{id}/result`:
  - `{ total_s, title, moments: [{ moment_id, start_s, end_s }] }`;
  - Review's moment list and the phone's duration check come from it.
- Jobs reuse `render_job.schema.json` unchanged. Errors are the same as `/v1/render`, plus the job-level `agent_failed` and `agent_timeout`.
- Examples: `contracts/examples/agent_request_{style}.json` and `agent_result_reels.json`. Update `contracts/README.md` ("Agent mode: `/v1/agent`") and `contracts/check.py`.

## Phase A1: Agent in the render service (PR `render/agent-mode`)

**Dependency:** `@anthropic-ai/claude-agent-sdk`, pinned exactly. Check `query()` and its options (`cwd`, `allowedTools`, `mcpServers` with `createSdkMcpServer`/`tool`, `canUseTool` or hooks, `maxTurns`, `abortController`, `model`) against code.claude.com/docs/en/agent-sdk when writing the code. Install `ffmpeg` in `cloud/Dockerfile` and `render/Dockerfile`.

### Files

| File | Purpose |
|---|---|
| `src/server/index.ts` | `POST /v1/agent` (multipart: `request` + one `{moment_id}.mp4` per clip), `GET /v1/agent/:id`, `/:id/result`, `/:id/video`. Reuses `auth`, the `multer` setup, `fail()`, and the reserve, cancel and 429 pattern of `/v1/render`. Extract the shared upload middleware rather than copying it. |
| `src/server/jobs.ts` | Generalize `Jobs` so a job runs either a `RenderFn` or a new `AgentFn` (`(input, workDir, onProgress, signal) => Promise<AgentResult>`). Both share the same concurrency slots, TTL sweep and delete-after-download. Store `result` beside `out.mp4`. |
| `src/server/validateAgent.ts` | Ajv against `agent_request.schema.json`, following `validate.ts`: the clip parts must match `clips[]`, and moment IDs must be unique. |
| `src/agent/run.ts` | `createAgentRunner(config): AgentFn`. Builds the workspace, calls `query()` with the system prompt, the tools below and the limits, and enforces `AGENT_TIMEOUT_S` with an `AbortController`. Logs turns, renders, `total_cost_usd` and elapsed time, never video. |
| `src/agent/prompt.ts` | System prompt. Taken from `backend/app/plan/prompt.py`: keep every button clip, chronological order, total within ±10% of `effective_target_s`, title text only from the destination, trip type and date, no invented events, no identifying people. Adds the composition contract and the order of work: look, plan, write, preview stills, render, check, submit. |
| `src/agent/workspace.ts` | Per-job dir under `AGENT_WORK_DIR` (default `render/.agent-work/`, gitignored; inside `render/` so imports resolve from `render/node_modules`). Contents: `public/clips/*.mp4`, `public/music` (symlink), `manifest.json` (request plus preset), the fixed `entry.ts` and `Root.tsx`, and a starter `src/Video.tsx`. |
| `src/agent/tools.ts` | MCP tools, see below. |
| `src/agent/template/` | The fixed `Root.tsx`, which registers `AgentVideo` with width, height and fps from the **preset** (not chosen by the agent). Its `durationInFrames` comes from `Video.tsx`'s exported `durationInFrames`. Also the starter `Video.tsx`. |
| `src/server/config.ts`, `.env.example` | `AGENT_MODEL` (default `claude-opus-5-5`), `AGENT_EFFORT` (`high`), `AGENT_MAX_TURNS` (60), `AGENT_TIMEOUT_S` (480), `AGENT_MAX_RENDERS` (3), `AGENTS_PER_TRIP` (3), `AGENT_WORK_DIR`. Uses the `ANTHROPIC_API_KEY` that is already a Fly secret. |

### Agent tools

- **Built-in:** only `Read`, `Write`, `Edit`, `Glob`, with `cwd` set to the workspace. A hook or `canUseTool` denies any path outside it. No Bash, web or other tools.
- **`look_at_clip(moment_id, times_s[] ≤ 6)`:** ffmpeg extracts JPEGs (384 px) and returns them as images. This is how the agent "watches" the clips. Count the calls.
- **`preview_frames(frames[] ≤ 6)`:** bundles the workspace (`@remotion/bundler`) and runs `renderStill` on `AgentVideo`. It returns PNGs, or the TypeScript, bundle or runtime error as text so the agent can fix it.
- **`render_video()`:** `renderMedia` to `out.mp4`, reusing `freePort()` and the `ensureBrowser` setup from `render/src/server/renderer.ts` (export them). Runs ffprobe and returns the duration, size and fps. Capped at `AGENT_MAX_RENDERS`. Its progress drives the job's progress.
- **`submit(result)`:** checks the result against `agent_result.schema.json` and the rules:
  - every button clip is in `moments`;
  - the moment IDs exist;
  - `total_s` is within ±10% of `effective_target_s` and within 0.5 s of ffprobe's duration;
  - `out.mp4` exists from the latest render.

  On failure it returns the errors so the agent can repair them. On success the job completes. If the agent ends without a valid submit, the job fails with `agent_failed`.

**Guidance in the prompt:** point the agent at `src/remotion/styles/*.tsx`, `speedRamp.ts` and `dipToBlack.tsx` as working examples it may import. Tell it to load clips only through `staticFile("clips/…")` and music through `staticFile("music/…")`, and to fetch nothing from the network.

### Tests (vitest)

- Request validation.
- The job lifecycle with a fake `AgentFn`: complete, fail, timeout or abort, 429 when a render is active, and delete after download.
- `submit` rule checks.
- The path guard rejects paths outside the workspace.
- `preview_frames` returns an error string, not a crash, when given a broken `Video.tsx`.

### Smoke

`scripts/agent-smoke.sh [style]` posts `agent_request_{style}.json` with the sample clips from `public/sample/`, polls, downloads, and checks the size, fps and duration against the result. It spends API money, so run it by hand, never in `npm test`.

## Phase A2: iOS integration (PR `ios/agent-mode`; RoamoryKit Edit and Cloud, coordinate with Daniel)

- `Resources/edit_config.json` and `EditConfig`:
  - `render_engine` accepts `"agent"`;
  - add `agent_timeout_s` (540, above the server's 480);
  - add `agent_upload_preset` (720p).
- Factor the multipart, poll and download code out of `Cloud/RemoteRenderClient.swift` into a small shared helper. Then add `Cloud/AgentRenderClient.swift`:
  1. Re-encode each prepared clip whole at the upload preset (a `ClipTrimmer` variant over `[0, duration]`).
  2. Upload and poll, then fetch `/result` before downloading the video (the download deletes the job).
  3. Run `Renderer.verify(expectedS: result.total_s)`.
  4. Return the video, the result and its moments.
- `Edit/EditCoordinator.swift`:
  - When `renderEngine == "agent"`, cloud analysis is on and a client exists, go straight to the agent after `PrePass` (phase "Claude is editing your video").
  - Set `planSource = "agent"` and `renderEngine = "agent"` with no `editSpec`, and build `reviewMoments` from `result.moments`.
  - On any error, log it and run the existing plan and render path unchanged.
- `RenderLabView`: add "Agent" to the engine picker, and show the elapsed time.
- **XCTest:**
  - `AgentRenderClient` with a `URLProtocol` stub: happy path, failed job, timeout;
  - the coordinator falls back to plan and render when the agent throws;
  - review moments come from the result.

## Risks

- **Time:** an agent loop plus at least one full render will likely take 3 to 8 minutes, against the 2-minute target. Agent mode is opt-in and the Processing screen must say it takes longer. Measure in A1.
- **Cost:** a run with images costs well above a single plan call. Log `total_cost_usd`; `AGENTS_PER_TRIP` and `AGENT_MAX_TURNS` cap it.
- **Agent-written code runs in headless Chrome on our server.** Mitigations:
  - the file tools can only write inside the workspace, and there is no Bash;
  - clips load only from local `staticFile`;
  - the job dir is deleted when the job ends;
  - the container holds no secrets other than the API key, which Chrome never sees.
- **Upload size:** up to 24 whole clips at 720p. This should fit `MAX_UPLOAD_MB=200`; check it on the phone.
- **One machine:** an agent job holds the single render slot for minutes, so a Remotion render request gets 429 and the phone falls back to rendering locally, which is acceptable.

## Verification

- `pip install jsonschema && python contracts/check.py` passes with the new schemas and examples.
- `cd render && npm test && npm run typecheck`.
- With `npm start` and a real key, run `scripts/agent-smoke.sh reels`. Then open the MP4 and confirm:
  - every button clip is in it;
  - the duration is within ±10% of the target;
  - the result's moment times line up with the video.

  Check the log for turns, renders and cost.
- Manual curl: `POST /v1/agent` with the example request and sample clips, then poll `/v1/agent/<id>`, then `GET /result` and `/video`.
- `cd ios/RoamoryKit && swift test`.
- On a phone, Render Lab with engine "Agent", then a real trip with `render_engine: "agent"`. Fault paths: server down, a forced `AGENT_TIMEOUT_S=5`, and a bad API key. Each must still produce a video through the normal path, with `planSource` "cloud" or "fallback".
