# Build from the repo root, since the service reads contracts/:
#   docker build -f render/Dockerfile -t roamory-render .
#   docker run --env-file .env -p 3000:3000 roamory-render
# Run render/scripts/sync-assets.sh first so render/public/ holds the music.
FROM node:22-bookworm-slim

# Chrome Headless Shell's shared libraries (remotion.dev/docs/docker).
RUN apt-get update && apt-get install -y --no-install-recommends \
      libnss3 libdbus-1-3 libatk1.0-0 libgbm-dev libasound2 libxrandr2 libxkbcommon-dev \
      libxfixes3 libxcomposite1 libxdamage1 libatk-bridge2.0-0 libpango-1.0-0 libcairo2 libcups2 \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY contracts/ contracts/
COPY render/package.json render/package-lock.json render/
RUN cd render && npm ci --no-audit --no-fund && npx remotion browser ensure
COPY render/ render/

WORKDIR /app/render
ENV PORT=3000
EXPOSE 3000
CMD ["npm", "start"]
