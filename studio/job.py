"""One studio job: its workspace, the Claude Code run that edits the video, and the checks on what it made."""
import json
import logging
import os
import shutil
import signal
import subprocess
import threading
import time
import uuid
from datetime import date
from pathlib import Path

from . import eta, rules
from .config import ROOT, Config

log = logging.getLogger("studio")
PROMPT = ROOT / "studio" / "prompt.md"
STYLES = ROOT / "studio" / "styles"
# Swift helpers, compiled into jobs/_bin (outside every workspace, so Claude cannot rewrite them).
BINARIES = {"card": "card.swift", "roamory-text": "text.swift", "roamory-music": "music.swift"}
TOOLS = ["Read", "Write", "Edit", "Glob", "Bash"]
ALLOWED = ["Read", "Write", "Edit", "Glob", "Bash(ffmpeg:*)", "Bash(ffprobe:*)", "Bash(roamory-text:*)",
           "Bash(roamory-music:*)"]


class JobError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def bin_dir(config: Config) -> Path:
    return config.jobs_path / "_bin"


def build_binaries(config: Config):
    """Compiles the Swift helpers, each again when its source changes."""
    for name, source in BINARIES.items():
        binary, source = bin_dir(config) / name, ROOT / "studio" / source
        if not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime:
            binary.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["xcrun", "swiftc", "-O", str(source), "-o", str(binary)], check=True, capture_output=True)


def title_for(request: dict) -> dict:
    """Title text only from the destination, trip type and start date (contracts README)."""
    ctx = request["context"]
    place = ctx["destination"]["city"] or ctx["destination"]["country"]
    month = date.fromisoformat(ctx["start_date"]).strftime("%B %Y")
    trip_type = ctx["trip_type"][:1].upper() + ctx["trip_type"][1:]
    return {"text": place[:40], "subtitle": f"{trip_type} · {month}"[:60]}


def claude_command(config: Config, prompt: str) -> list[str]:
    return [config.claude, "-p", prompt,
            "--model", config.model,
            "--max-turns", str(config.max_turns),
            "--max-budget-usd", str(config.max_budget_usd),
            "--output-format", "stream-json", "--verbose",
            "--no-session-persistence",
            # No user or project settings, file tools confined to the workspace, no MCP servers.
            "--restricted", "--strict-mcp-config",
            "--tools", *TOOLS,
            "--allowedTools", *ALLOWED,
            "--permission-mode", "dontAsk"]


def stage_from_event(event: dict) -> str | None:
    """A short progress line from one stream-json event: Claude's own STAGE: line, else its Bash description."""
    if event.get("type") != "assistant":
        return None
    stage = None
    for block in event.get("message", {}).get("content", []):
        if block.get("type") == "text":
            for line in block.get("text", "").splitlines():
                if line.strip().startswith("STAGE:"):
                    stage = line.strip()[len("STAGE:"):].strip()
        elif block.get("type") == "tool_use" and stage is None and block.get("name") == "Bash":
            stage = block.get("input", {}).get("description")
    return stage[:80] if stage else None


class Job:
    def __init__(self, request: dict, config: Config):
        self.id = "j_" + uuid.uuid4().hex[:12]
        self.request = request
        self.config = config
        self.dir = config.jobs_path / self.id
        self.status = "uploading"
        self.stage: str | None = None
        self.error: dict | None = None
        self.result: dict | None = None
        self.started_at: float | None = None
        self.guess_s = 0.0
        self.estimate_s: float | None = None
        self.touched_at = time.time()
        self._proc: subprocess.Popen | None = None
        self._cancelled = False
        self.clip_ids = [c["clip_id"] for c in request["clips"]]
        (self.dir / "clips").mkdir(parents=True)

    # Upload

    def clip_path(self, clip_id: str) -> Path:
        return self.dir / "clips" / f"{clip_id}.mp4"

    def missing_clips(self) -> list[str]:
        return [i for i in self.clip_ids if not self.clip_path(i).exists()]

    # State

    @property
    def active(self) -> bool:
        return self.status in ("uploading", "editing")

    def to_json(self) -> dict:
        elapsed = (time.time() if self.status == "editing" else self.touched_at) - self.started_at if self.started_at else 0
        remaining = None
        if self.status == "editing" and self.estimate_s is not None:
            remaining = round(max(self.estimate_s - elapsed, 0))
        return {"job_id": self.id, "status": self.status, "stage": self.stage,
                "elapsed_s": round(max(elapsed, 0), 1), "eta_s": remaining, "error": self.error}

    @property
    def video(self) -> Path:
        return self.dir / "out" / "video.mp4"

    def _fail(self, code: str, message: str):
        self.status, self.stage = "failed", None
        self.error = {"code": code, "message": message[:500], "retryable": False}
        self.touched_at = time.time()
        log.warning("job %s failed: %s %s", self.id, code, message)

    # Edit

    def start(self):
        clip_bytes = sum(self.clip_path(i).stat().st_size for i in self.clip_ids)
        self.guess_s, self.estimate_s = eta.estimate_s(self.config, self.request, clip_bytes)
        log.info("job %s: estimated %.0f s with %s", self.id, self.estimate_s, self.config.model)
        self.status, self.stage, self.started_at = "editing", "Starting Claude", time.time()
        threading.Thread(target=self._run, name=self.id, daemon=True).start()

    def cancel(self):
        self._cancelled = True
        self._kill()

    def _kill(self):
        if self._proc and self._proc.poll() is None:
            os.killpg(self._proc.pid, signal.SIGKILL)

    def _prepare(self) -> str:
        preset = rules.preset(self.request["style"])
        title = title_for(self.request)
        for k in ("frames", "work", "out", "cards"):
            (self.dir / k).mkdir(exist_ok=True)
        for clip_id in self.clip_ids:
            (self.dir / "frames" / clip_id).mkdir(exist_ok=True)
        w, h = preset["output"]["width"], preset["output"]["height"]
        build_binaries(self.config)
        card = str(bin_dir(self.config) / "card")
        style = self.request["style"]
        for name, mode, text, sub in [("title", "opaque", title["text"], title["subtitle"]),
                                      ("title_overlay", "overlay", title["text"], title["subtitle"]),
                                      ("end", "opaque", "Made with Roamory", "")]:
            subprocess.run([card, str(self.dir / "cards" / f"{name}.png"), str(w), str(h), style, mode, text, sub],
                           check=True, capture_output=True)
        brief = {
            "style": style, "preset": preset, "context": self.request["context"], "title": title,
            "effective_target_s": rules.effective_target_s(self.request),
            "max_renders": self.config.max_renders,
            "clips": [{**c, "file": f"clips/{c['clip_id']}.mp4"} for c in self.request["clips"]],
        }
        (self.dir / "brief.json").write_text(json.dumps(brief, indent=2))
        shutil.copy(STYLES / f"{style}.md", self.dir / "style.md")
        return PROMPT.read_text()

    def _run(self):
        try:
            prompt = self._prepare()
        except Exception as e:  # noqa: BLE001 - any setup failure fails the job
            return self._fail("internal", f"could not prepare the workspace: {e}")
        cmd = claude_command(self.config, prompt)
        log.info("job %s: running Claude (%s, %d clips)", self.id, self.request["style"], len(self.clip_ids))
        timed_out = threading.Event()

        def on_timeout():
            timed_out.set()
            self._kill()

        timer = threading.Timer(self.config.timeout_s, on_timeout)
        summary = {}
        stderr_path = self.dir / "claude.stderr"
        env = {**os.environ, "PATH": f"{bin_dir(self.config)}{os.pathsep}{os.environ.get('PATH', '')}"}
        try:
            with open(stderr_path, "w") as stderr:
                self._proc = subprocess.Popen(cmd, cwd=self.dir, stdout=subprocess.PIPE, stderr=stderr, text=True,
                                              env=env, start_new_session=True)
                timer.start()
                for line in self._proc.stdout:
                    try:
                        event = json.loads(line)
                    except ValueError:
                        continue
                    if stage := stage_from_event(event):
                        self.stage = stage
                    if event.get("type") == "result":
                        summary = event
                self._proc.wait()
        except OSError as e:
            return self._fail("internal", f"could not run {self.config.claude}: {e}")
        finally:
            timer.cancel()
        log.info("job %s: Claude exited %s after %.0f s, %s turns, $%s", self.id, self._proc.returncode,
                 time.time() - self.started_at, summary.get("num_turns"), summary.get("total_cost_usd"))
        if self._cancelled:
            return self._fail("agent_failed", "cancelled")
        if timed_out.is_set():
            return self._fail("agent_timeout", f"Claude did not finish within {self.config.timeout_s:g} s.")
        self._check(summary, stderr_path)

    def _check(self, summary: dict, stderr_path: Path):
        result_path = self.dir / "out" / "result.json"
        if not result_path.exists():
            why = summary.get("result") or summary.get("subtype") or stderr_path.read_text()[-300:] or "no result.json"
            return self._fail("agent_failed", f"Claude wrote no result: {why}")
        try:
            result = json.loads(result_path.read_text())
        except ValueError as e:
            return self._fail("agent_failed", f"result.json is not JSON: {e}")
        errors = rules.result_errors(result, self.request, self.video)
        if errors:
            return self._fail("agent_failed", "; ".join(errors))
        self.result = result
        self.status, self.stage = "completed", "Done"
        self.touched_at = time.time()
        try:
            eta.record(self.config, self.guess_s, self.touched_at - self.started_at)
        except OSError as e:
            log.warning("could not record the run time: %s", e)
        log.info("job %s completed: %.1f s video", self.id, result["total_s"])

    def delete(self):
        self.cancel()
        shutil.rmtree(self.dir, ignore_errors=True)
