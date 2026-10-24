# The backend and the render service in one container for Fly.io, behind Caddy (cloud/Caddyfile).
# Build from the repo root, after render/scripts/sync-assets.sh so render/public/ holds the music:
#   docker build -f cloud/Dockerfile -t roamory .
#   docker run --env-file .env -e PORT=8080 -p 8080:8080 roamory   (.env's PORT is the render service's)
# scripts/deploy.sh builds and deploys this image.
FROM caddy:2 AS caddy

FROM node:22-bookworm-slim
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy

# Chrome Headless Shell's shared libraries (remotion.dev/docs/docker), ffmpeg for agent mode's frames and ffprobe, and Python 3.11 for the backend.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libnss3 libdbus-1-3 libatk1.0-0 libgbm-dev libasound2 libxrandr2 libxkbcommon-dev \
      libxfixes3 libxcomposite1 libxdamage1 libatk-bridge2.0-0 libpango-1.0-0 libcairo2 libcups2 \
      ca-certificates python3 python3-venv ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY contracts/ contracts/
COPY render/package.json render/package-lock.json render/
RUN cd render && npm ci --no-audit --no-fund && npx remotion browser ensure
COPY backend/ backend/
# Editable, so app/config.py's REPO_ROOT stays /app and finds contracts/.
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir -e ./backend
COPY render/ render/
COPY cloud/ cloud/

ENV PORT=8080
EXPOSE 8080
CMD ["cloud/start.sh"]
