#!/usr/bin/env bash
# Points the app at the render service on this Mac: writes Local.xcconfig with this Mac's
# Bonjour name, $PORT and $APP_TOKEN (repo-root .env, then render/.env, as the server reads them).
# With no APP_TOKEN set, it generates one into render/.env. Usage: use-laptop-render.sh [host]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"

read_env() {  # last value wins, like the server (render/.env overrides the root .env)
  local value=""
  for f in "$root/.env" "$root/render/.env"; do
    [[ -f "$f" ]] || continue
    local line; line="$(grep -E "^$1=" "$f" | tail -1 || true)"
    [[ -n "$line" ]] && value="${line#*=}"
  done
  echo "$value"
}

token="$(read_env APP_TOKEN)"
if [[ -z "$token" || "$token" == "change-me" ]]; then
  token="$(openssl rand -hex 16)"
  echo "APP_TOKEN=$token" >> "$root/render/.env"
  echo "Generated APP_TOKEN into render/.env"
fi
port="$(read_env PORT)"; port="${port:-3000}"
host="${1:-$(scutil --get LocalHostName).local}"

# Keep a backend URL set by hand
api="$(grep -E '^ROAMORY_API_BASE_URL' "$here/Local.xcconfig" 2>/dev/null || true)"
cat > "$here/Local.xcconfig" <<XC
// Written by use-laptop-render.sh. Untracked; never commit the token.
ROAMORY_RENDER_BASE_URL = http:/\$()/$host:$port
ROAMORY_APP_TOKEN = $token
$api
XC
echo "App will render on http://$host:$port. Rebuild the app, then start the server: cd render && npm start"
