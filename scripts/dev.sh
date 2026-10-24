#!/usr/bin/env bash
# Runs the backend (uvicorn, port 8000) and the render service (npm start, $PORT or 3000) together,
# both reachable from the phone on this Mac's network. Logs are prefixed [api] and [render].
# Ctrl-C stops both; if either one exits, the other is stopped too.
# Needs the backend venv and render/node_modules (setup in CLAUDE.md). Usage: scripts/dev.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

[[ -x "$root/backend/.venv/bin/uvicorn" ]] || { echo "No backend venv. See Backend setup in CLAUDE.md." >&2; exit 1; }
[[ -d "$root/render/node_modules" ]] || { echo "No render/node_modules. Run: cd render && npm ci" >&2; exit 1; }

read_env() {  # last value wins, like the render server (render/.env overrides the root .env)
  local value=""
  for f in "$root/.env" "$root/render/.env"; do
    [[ -f "$f" ]] || continue
    local line; line="$(grep -E "^$1=" "$f" | tail -1 || true)"
    [[ -n "$line" ]] && value="${line#*=}"
  done
  echo "$value"
}
api_port="${BACKEND_PORT:-8000}"
render_port="$(read_env PORT)"; render_port="${render_port:-3000}"
for port in "$api_port" "$render_port"; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $port is already in use. Stop whatever is on it first." >&2; exit 1
  fi
done

prefix() { awk -v p="$1" '{ print p " " $0; fflush() }'; }

(cd "$root/backend" && exec .venv/bin/uvicorn app.main:app --reload --host 0.0.0.0 --port "$api_port") \
  > >(prefix "[api]") 2>&1 &
api=$!
(cd "$root/render" && exec npm start) > >(prefix "[render]") 2>&1 &
render=$!

stop() {
  trap - INT TERM EXIT
  for pid in "$api" "$render"; do
    pkill -TERM -P "$pid" 2>/dev/null || true
    kill -TERM "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}
trap 'stop; exit 0' INT TERM
trap stop EXIT

host="$(scutil --get LocalHostName).local"
echo "Backend: http://$host:$api_port   Render: http://$host:$render_port   (Ctrl-C stops both)"

while kill -0 "$api" 2>/dev/null && kill -0 "$render" 2>/dev/null; do sleep 1; done
echo "A server exited; stopping the other." >&2
