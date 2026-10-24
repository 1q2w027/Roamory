#!/usr/bin/env bash
# One-time Fly.io setup for scripts/deploy.sh: creates the app and stores ANTHROPIC_API_KEY and
# APP_TOKEN from .env as Fly secrets. Safe to rerun; rerun after changing either value in .env, then
# redeploy. Needs fly auth login. Usage: scripts/cloud-setup.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/cloud-env.sh"

fly status --app "$app" >/dev/null 2>&1 || {
  org="$(read_env FLY_ORG)"
  fly apps create "$app" --org "${org:-personal}"
}

token="$(read_env APP_TOKEN)"
if [[ -z "$token" || "$token" == "change-me" ]]; then
  token="$(openssl rand -hex 16)"
  echo "APP_TOKEN=$token" >> "$root/.env"
  echo "Generated APP_TOKEN into .env"
fi
key="$(read_env ANTHROPIC_API_KEY)"
[[ -n "$key" ]] || { echo "Set ANTHROPIC_API_KEY in .env." >&2; exit 1; }

# Through stdin so the values stay out of the process list.
printf 'ANTHROPIC_API_KEY=%s\nAPP_TOKEN=%s\n' "$key" "$token" | fly secrets import --app "$app" --stage
echo "Ready. Next: scripts/deploy.sh"
