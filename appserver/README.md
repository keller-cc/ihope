# appserver

配置：本目录 `.env`（见 `.env.example`）。

## 本地

```powershell
cd d:\IHope\appserver
copy .env.example .env
docker compose up -d
go run ./cmd/appserver
```

前端：`cd web && pnpm run dev` → http://localhost:5173

## VPS

```bash
cd /opt/ihope/deploy && docker compose down
cd /opt/ihope/appserver
# 改 .env（见下）
cp nginx.conf.example nginx.conf
docker compose -f docker-compose.prod.yml up -d --build
```

`.env` 生产必改：`WEB_DB_PASSWORD`、`CORS_ORIGIN`、`APP_PUBLIC_URL`、`JWT_SECRET`、`ADMIN_TOKEN`、`MESSAGE_ENCRYPTION_KEY`；邮件/QQ 从旧 `deploy/.env` 搬过来即可。`nginx.conf` 的 `server_name` 与域名一致。
