"""Roamory Studio: the Mac bridge the iPhone sends a trip's clips to, for Claude Code to edit (contracts README,
"/v1/studio"). Run: python -m studio.server"""
import hmac
import json
import logging
import re
import secrets
import shutil
import socket
import subprocess
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import config as config_module
from . import rules
from .job import Job

log = logging.getLogger("studio")
CHUNK = 1 << 20
MAX_JSON = 1 << 20
MAX_PAIR_FAILURES = 5


class Studio:
    """Pairing and the jobs; shared by every request thread."""

    def __init__(self, config: config_module.Config):
        self.config = config
        self.lock = threading.Lock()
        self.jobs: dict[str, Job] = {}
        config.state_path.mkdir(parents=True, exist_ok=True)
        token_file = config.state_path / "token"
        if not token_file.exists():
            token_file.write_text(secrets.token_urlsafe(24))
            token_file.chmod(0o600)
        self.token = token_file.read_text().strip()
        self.name = socket.gethostname().removesuffix(".local")
        self.pair_failures = 0
        self.new_code()

    def new_code(self):
        self.code = f"{secrets.randbelow(1_000_000):06d}"
        self.pair_failures = 0
        print(f"\n  Roamory Studio pairing code: {self.code}\n", flush=True)

    def pair(self, code: str) -> bool:
        with self.lock:
            if hmac.compare_digest(code, self.code):
                return True
            self.pair_failures += 1
            if self.pair_failures >= MAX_PAIR_FAILURES:
                self.new_code()
            return False

    def sweep(self):
        """Deletes jobs untouched for job_ttl_min: finished and never downloaded, or abandoned mid-upload."""
        cutoff = time.time() - self.config.job_ttl_min * 60
        with self.lock:
            stale = [j for j in self.jobs.values() if j.status != "editing" and j.touched_at < cutoff]
            for job in stale:
                del self.jobs[job.id]
        for job in stale:
            log.info("job %s expired", job.id)
            job.delete()


def error(code: str, message: str, retryable: bool = False) -> dict:
    return {"code": code, "message": message, "retryable": retryable}


ROUTES = []


def route(method: str, pattern: str, auth: bool = True):
    def wrap(fn):
        ROUTES.append((method, re.compile(f"^{pattern}$"), auth, fn))
        return fn
    return wrap


class Handler(BaseHTTPRequestHandler):
    studio: Studio
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        log.debug("%s %s", self.address_string(), fmt % args)

    def _dispatch(self, method: str):
        path = self.path.split("?", 1)[0]
        matched_path = False
        for m, pattern, auth, fn in ROUTES:
            match = pattern.match(path)
            if not match:
                continue
            matched_path = True
            if m != method:
                continue
            if auth and not self._authorized():
                return self.send_json(401, error("unauthorized", "Pair with this Mac first."))
            try:
                return fn(self, *match.groups())
            except Exception as e:  # noqa: BLE001 - report, never drop the connection silently
                log.exception("%s %s failed", method, path)
                return self.send_json(500, error("internal", str(e)))
        status = 405 if matched_path else 404
        self.send_json(status, error("not_found", f"No route for {method} {path}"))

    def do_GET(self): self._dispatch("GET")
    def do_POST(self): self._dispatch("POST")
    def do_PUT(self): self._dispatch("PUT")
    def do_DELETE(self): self._dispatch("DELETE")

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        return header.startswith("Bearer ") and hmac.compare_digest(header[7:], self.studio.token)

    def send_json(self, status: int, body, headers: dict | None = None):
        if status >= 400:
            # The request body may be unread, so this connection cannot carry another request.
            self.close_connection = True
        data = json.dumps(body).encode()
        self.send_response(status)
        if self.close_connection:
            self.send_header("Connection", "close")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def send_empty(self, status: int):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_JSON:
            raise ValueError("body too large")
        return json.loads(self.rfile.read(length) or b"null")

    def job(self, job_id: str) -> Job | None:
        with self.studio.lock:
            return self.studio.jobs.get(job_id)


@route("GET", "/healthz", auth=False)
def healthz(h: Handler):
    h.send_json(200, {"ok": True, "name": h.studio.name})


@route("POST", "/v1/studio/pair", auth=False)
def pair(h: Handler):
    try:
        code = str(h.read_json()["code"])
    except (ValueError, KeyError, TypeError):
        return h.send_json(400, error("bad_request", 'Send {"code": "123456"}.'))
    if not h.studio.pair(code):
        return h.send_json(401, error("unauthorized", "Wrong pairing code. Check the code shown on the Mac."))
    log.info("paired with %s", h.address_string())
    h.send_json(200, {"token": h.studio.token, "name": h.studio.name})


@route("POST", "/v1/studio/jobs")
def create_job(h: Handler):
    try:
        request = h.read_json()
    except ValueError as e:
        return h.send_json(400, error("bad_request", f"Request is not JSON: {e}"))
    if errors := rules.request_errors(request):
        return h.send_json(400, error("bad_request", "; ".join(errors)[:500]))
    with h.studio.lock:
        if any(j.active for j in h.studio.jobs.values()):
            return h.send_json(429, error("busy", "This Mac is already making a video.", retryable=True))
        job = Job(request, h.studio.config)
        h.studio.jobs[job.id] = job
    log.info("job %s created: %d clips, %s", job.id, len(job.clip_ids), request["style"])
    h.send_json(201, {"job_id": job.id})


@route("PUT", r"/v1/studio/jobs/([\w-]+)/clips/([A-Za-z0-9_-]{1,64})\.mp4")
def upload_clip(h: Handler, job_id: str, clip_id: str):
    job = h.job(job_id)
    if job is None or clip_id not in job.clip_ids:
        return h.send_json(404, error("not_found", "No such job or clip."))
    if job.status != "uploading":
        return h.send_json(409, error("conflict", "The job has already started."))
    length = int(h.headers.get("Content-Length") or 0)
    if length <= 0:
        return h.send_json(400, error("bad_request", "Content-Length is required."))
    if length > h.studio.config.max_clip_mb * 1024 * 1024:
        return h.send_json(413, error("upload_too_large", f"Clips are limited to {h.studio.config.max_clip_mb} MB."))
    path = job.clip_path(clip_id)
    partial = path.with_suffix(".part")
    with open(partial, "wb") as f:
        remaining = length
        while remaining:
            chunk = h.rfile.read(min(CHUNK, remaining))
            if not chunk:
                break
            f.write(chunk)
            remaining -= len(chunk)
    if remaining:
        partial.unlink(missing_ok=True)
        return h.send_json(400, error("bad_request", "Upload ended early."))
    partial.replace(path)
    job.touched_at = time.time()
    h.send_empty(204)


@route("POST", r"/v1/studio/jobs/([\w-]+)/start")
def start_job(h: Handler, job_id: str):
    job = h.job(job_id)
    if job is None:
        return h.send_json(404, error("not_found", "No such job."))
    if job.status != "uploading":
        return h.send_json(409, error("conflict", "The job has already started."))
    if missing := job.missing_clips():
        return h.send_json(400, error("bad_request", f"Clips not uploaded: {', '.join(missing)}"))
    job.start()
    h.send_json(202, job.to_json())


@route("GET", r"/v1/studio/jobs/([\w-]+)")
def get_job(h: Handler, job_id: str):
    job = h.job(job_id)
    if job is None:
        return h.send_json(404, error("not_found", "No such job."))
    h.send_json(200, job.to_json())


@route("DELETE", r"/v1/studio/jobs/([\w-]+)")
def delete_job(h: Handler, job_id: str):
    with h.studio.lock:
        job = h.studio.jobs.pop(job_id, None)
    if job is None:
        return h.send_json(404, error("not_found", "No such job."))
    job.delete()
    h.send_empty(204)


@route("GET", r"/v1/studio/jobs/([\w-]+)/result")
def get_result(h: Handler, job_id: str):
    job = h.job(job_id)
    if job is None or job.status != "completed":
        return h.send_json(404, error("not_found", "No finished video for this job."))
    h.send_json(200, job.result)


@route("GET", r"/v1/studio/jobs/([\w-]+)/video")
def get_video(h: Handler, job_id: str):
    job = h.job(job_id)
    if job is None or job.status != "completed":
        return h.send_json(404, error("not_found", "No finished video for this job."))
    size = job.video.stat().st_size
    h.send_response(200)
    h.send_header("Content-Type", "video/mp4")
    h.send_header("Content-Length", str(size))
    h.end_headers()
    with open(job.video, "rb") as f:
        shutil.copyfileobj(f, h.wfile, CHUNK)
    with h.studio.lock:
        h.studio.jobs.pop(job_id, None)
    job.delete()
    log.info("job %s downloaded and deleted", job_id)


def advertise(port: int) -> subprocess.Popen | None:
    """Bonjour: _roamory._tcp with the Mac's .local name in the TXT record, so the phone needs no resolve step."""
    try:
        local = subprocess.run(["scutil", "--get", "LocalHostName"], capture_output=True, text=True,
                               check=True).stdout.strip()
        return subprocess.Popen(["dns-sd", "-R", f"Roamory Studio on {local}", "_roamory._tcp", "local", str(port),
                                 f"host={local}.local", f"port={port}", "v=1"],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError) as e:
        log.warning("Bonjour advertising failed (%s); the phone will not find this Mac", e)
        return None


def make_server(config: config_module.Config, port: int | None = None) -> ThreadingHTTPServer:
    studio = Studio(config)
    handler = type("BoundHandler", (Handler,), {"studio": studio})
    server = ThreadingHTTPServer(("0.0.0.0", config.port if port is None else port), handler)
    server.daemon_threads = True
    server.studio = studio
    return server


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    config = config_module.load()
    for tool in ("ffmpeg", "ffprobe", config.claude):
        if shutil.which(tool) is None:
            raise SystemExit(f"{tool} not found on PATH")
    server = make_server(config)
    bonjour = advertise(config.port)

    def sweeper():
        while True:
            time.sleep(60)
            server.studio.sweep()

    threading.Thread(target=sweeper, daemon=True).start()
    log.info("Roamory Studio listening on port %d", config.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if bonjour:
            bonjour.terminate()
        for job in list(server.studio.jobs.values()):
            job.delete()


if __name__ == "__main__":
    main()
