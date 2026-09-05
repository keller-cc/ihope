FROM node:22-bookworm-slim AS web
WORKDIR /src/web
ENV CI=true
ENV PNPM_HOME=/pnpm
ENV PATH=$PNPM_HOME:$PATH
RUN npm install -g pnpm@10.32.0
COPY web/package.json web/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY web/ .
RUN pnpm run build

FROM golang:1.25-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /src/appserver
COPY appserver/go.mod appserver/go.sum ./
RUN go mod download
COPY appserver/ .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /appserver ./cmd/appserver

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
