#!/usr/bin/env bash
# Builds cloud/Dockerfile (the backend and render service in one image, linux/amd64), pushes it to
# Fly's registry and deploys it with cloud/fly.toml. Exactly one machine: budgets and render jobs live
# in memory. Needs scripts/cloud-setup.sh once, and render/scripts/sync-assets.sh first. Usage: scripts/deploy.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/cloud-env.sh"

ls "$root"/render/public/music/* >/dev/null 2>&1 || { echo "No music in render/public. Run render/scripts/sync-assets.sh." >&2; exit 1; }

env_flags=()  # the non-secret settings in .env.example, with values from .env when set
for key in STAGE2A_MODEL PLANNER_MODEL PLANNER_EFFORT PLAN_TIMEOUT_S \
    MAX_PLAN_CLIPS PLANS_PER_TRIP STAGE2A_EFFORT STAGE2A_TIMEOUT_S \
    BUCKET_CAPACITY BUCKET_REFILL_S \
    FAST_PER_HOUR DESCRIBE_PER_HOUR DEMO_MODE RENDER_CONCURRENCY RENDER_TTL_S MAX_UPLOAD_MB \
    AGENT_MODEL AGENT_EFFORT AGENT_MAX_TURNS AGENT_TIMEOUT_S AGENT_MAX_RENDERS AGENTS_PER_TRIP; do
  value="$(read_env "$key")"
  [[ -n "$value" ]] || value="$(grep -E "^$key=" "$root/.env.example" | tail -1 | cut -d= -f2-)"
  [[ -n "$value" ]] && env_flags+=(--env "$key=$value")
done

# Built here rather than by fly deploy so BuildKit applies cloud/Dockerfile.dockerignore. Loaded,
# then pushed with docker push: Fly's registry rejects a push from a docker-container buildx builder.
image="registry.fly.io/$app:$(git -C "$root" rev-parse --short HEAD)-$(date +%s)"
docker buildx build --platform linux/amd64 --provenance=false --sbom=false \
  -f "$root/cloud/Dockerfile" -t "$image" --load "$root"
fly auth docker  # after the build: its registry login expires in minutes
docker push "$image"

# --ha=false keeps it to one machine.
fly deploy --app "$app" --config "$root/cloud/fly.toml" --image "$image" \
  --primary-region "$region" --ha=false "${env_flags[@]}"

echo "roamory: https://$app.fly.dev"
echo "Point the app at it: scripts/use-cloud.sh"
