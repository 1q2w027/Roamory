#!/usr/bin/env bash
# Points the app at the Fly.io app: writes the untracked ios/Roamory/Config/Local.xcconfig with its
# URL (backend and render share it) and the app token from .env (Fly secrets can't be read back).
# Rebuild the app afterwards. ios/Roamory/Config/use-laptop-render.sh points it back at this Mac.
# Usage: scripts/use-cloud.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/cloud-env.sh"

host="$app.fly.dev"
token="$(read_env APP_TOKEN)"
[[ -n "$token" && "$token" != "change-me" ]] || { echo "No APP_TOKEN in .env. Run scripts/cloud-setup.sh." >&2; exit 1; }
cat > "$root/ios/Roamory/Config/Local.xcconfig" <<XC
// Written by scripts/use-cloud.sh. Untracked; never commit the token.
ROAMORY_API_BASE_URL = https:/\$()/$host
ROAMORY_RENDER_BASE_URL = https:/\$()/$host
ROAMORY_APP_TOKEN = $token
XC
echo "App will use https://$host for the backend and rendering. Rebuild the app."
