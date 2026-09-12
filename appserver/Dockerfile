# syntax=docker/dockerfile:1

# Web + Go stages can run in parallel under BuildKit (heavy on Docker Desktop).
# Tip (Windows): Docker Desktop → Settings → Resources — leave ≥2 CPU / 4GB for the host.
# Tip: limit BuildKit workers via Docker Engine JSON: "builder": { "gc": { ... } }
#   or create a builder with buildkitd.toml: [worker.oci] max-parallelism = 2

FROM node:22-bookworm-slim AS web
WORKDIR /src/web
ENV CI=true
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
# Fewer Vite/tsc workers → less host stutter on small machines
ENV NODE_OPTIONS=--max-old-space-size=2048
RUN npm install -g pnpm@10.32.0
COPY web/package.json web/pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile
COPY web/ .
RUN --mount=type=cache,id=web-vite,target=/src/web/node_modules/.vite \
    pnpm run build

FROM golang:1.25-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /src/appserver
# Cap Go compile parallelism so it does not fight the Node stage / host UI
ENV GOMAXPROCS=2
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
