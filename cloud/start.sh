#!/usr/bin/env bash
# Container entry: the backend on :8001 and the render service on :3001, behind Caddy on $PORT
# (cloud/Caddyfile). If any of them exits, the container exits and Fly restarts it.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd backend && PORT=8001 exec /opt/venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8001) &
(cd render && PORT=3001 exec npm start) &
caddy run --config cloud/Caddyfile --adapter caddyfile &
wait -n
exit 1
