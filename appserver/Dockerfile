# syntax=docker/dockerfile:1
#
# Peak CPU is the main pain on Docker Desktop (Windows VM). This file:
# 1) finishes the web build before starting Go (no parallel compile spikes)
# 2) skips tsc in-image (CI/dev still run `pnpm build`)
# 3) reuses pnpm / Go caches across builds
#
# Tip: Docker Desktop → Resources — leave ≥2 CPU / 4GB for the host.

FROM node:22-bookworm-slim AS web
WORKDIR /src/web
ENV CI=true
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
ENV NODE_OPTIONS=--max-old-space-size=1536
# Keep Vite/Node from spawning too many helpers beside the Go stage later.
ENV UV_THREADPOOL_SIZE=2
RUN corepack enable && corepack prepare pnpm@10.32.0 --activate
COPY web/package.json web/pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile
COPY web/ .
# Docker image: vite only (typecheck locally / in CI).
RUN --mount=type=cache,id=web-vite,target=/src/web/node_modules/.vite \
    pnpm run build:docker

FROM golang:1.25-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /src/appserver
# Serialize: do not touch Go modules until web dist exists (halves peak CPU).
COPY --from=web /src/web/dist/index.html /tmp/web-ready.html
ENV GOMAXPROCS=1
COPY appserver/go.mod appserver/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
COPY appserver/ .
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /appserver ./cmd/appserver

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /appserver /app/appserver
COPY --from=web /src/web/dist /app/web
ENV HTTP_ADDR=:8090
ENV WEB_DIST=/app/web
ENV UPLOAD_DIR=/data/uploads
EXPOSE 8090
VOLUME ["/data/uploads"]
CMD ["/app/appserver"]
