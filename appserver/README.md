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

### Docker 构建卡顿（尤其 Windows）

`Dockerfile` 会先 `pnpm build:docker`（仅 Vite），完成后再 `go build`（不再与前端并行），并限制 `GOMAXPROCS=1`。

建议：

1. **日常开发不要 `--build`**：本机 `docker compose up -d`（仅 Postgres）+ `go run` + `pnpm dev`。
2. **Docker Desktop → Settings → Resources**：CPU 设为物理核数的一半左右，内存留 ≥4GB 给宿主机。
3. 二次构建会复用 pnpm/go 缓存；只改 `appserver/` 时仍会等 web 层（为压峰值做了串行）。若 web 未变，BuildKit 会命中 web 缓存后很快进入 Go。
4. 类型检查：镜像内跳过 `tsc`；本地/CI 继续用 `pnpm build`。

`.env` 生产必改：`WEB_DB_PASSWORD`、`CORS_ORIGIN`、`APP_PUBLIC_URL`、`JWT_SECRET`、`ADMIN_TOKEN`、`MESSAGE_ENCRYPTION_KEY`；邮件/QQ 从旧 `deploy/.env` 搬过来即可。`nginx.conf` 的 `server_name` 与域名一致。

QQ 生产示例：

```env
QQ_BOT_ENABLED=true
QQ_QUOTES_FILE_PATH=/opt/ihope/quotes/quotes.example.txt
QQ_POETRY_FONT_PATH=/opt/ihope/fonts/NotoSansSC-Regular.otf
QQ_DAILY_POETRY_HHMM=08:00
QQ_DAILY_QUOTES_HHMM=08:02
QQ_DAILY_NEWS_HHMM=08:05
```

字体放到 `deploy/fonts/`（勿提交），compose 会挂到 `/opt/ihope/fonts`。
