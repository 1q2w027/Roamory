# Shared by cloud-setup.sh, deploy.sh and use-cloud.sh. Source it; needs $root set to the repo root.
read_env() {  # last value in the repo-root .env, like the servers read it
  local line; line="$(grep -E "^$1=" "$root/.env" 2>/dev/null | tail -1 || true)"
  echo "${line#*=}"
}
app="$(read_env FLY_APP)"
region="$(read_env FLY_REGION)"; region="${region:-sjc}"
[[ -n "$app" ]] || { echo "Set FLY_APP in .env (see .env.example)." >&2; exit 1; }
