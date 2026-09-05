FROM node:22-alpine AS web
WORKDIR /src/web
COPY web/package.json web/pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY web/ .
RUN pnpm run build

FROM golang:1.25-alpine AS builder
RUN apk add --no-cache ca-certificates
WORKDIR /src/appserver
COPY appserver/go.mod appserver/go.sum ./
RUN go mod download
COPY appserver/ .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /appserver ./cmd/appserver

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /appserver /app/appserver
COPY --from=web /src/web/dist /app/web
ENV HTTP_ADDR=:8090
ENV WEB_DIST=/app/web
ENV UPLOAD_DIR=/data/uploads
EXPOSE 8090
VOLUME ["/data/uploads"]
CMD ["/app/appserver"]
