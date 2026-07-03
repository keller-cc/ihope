# 构建上下文：仓库根目录（见 deploy/docker-compose.yml）
FROM golang:1.22-alpine AS builder
RUN apk add --no-cache ca-certificates
WORKDIR /src/backend
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /server /app/server
COPY admin /app/admin
ENV ADMIN_WEB_DIR=/app/admin
ENV UPLOAD_DIR=/data/uploads
EXPOSE 8080
VOLUME ["/data/uploads"]
CMD ["/app/server"]
