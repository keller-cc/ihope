# appserver

Web IM 后端。配置全部在本目录 `.env`（模板：`.env.example`）。

## 与旧栈隔离

| | 旧 App | Web IM |
|--|--|--|
| Compose | `deploy/docker-compose.dev.yml` | `appserver/docker-compose.yml` |
| 端口 | 5433 · 库 `ihope` | **5434** · 库 **`ihope_web`** |
| HTTP | `:8080` | **`:8090`** |
| 配置 | `deploy/.env` | **`appserver/.env`** |

## 本地运行

```powershell
# 1. 库
cd d:\IHope\appserver
copy .env.example .env
docker compose up -d

# 2. API
go run ./cmd/appserver

# 3. 前端（另开终端）
cd d:\IHope\web
pnpm install
pnpm run dev
```

- 前端：http://localhost:5173  
- 健康检查：http://localhost:8090/health  
- 管理页：http://localhost:5173/admin（`ADMIN_TOKEN`）  
- 双账号：`?slot=a` / `?slot=b`

SMTP / QQ 等在 `appserver/.env` 填写；`MAIL_DRIVER=log` 时验证链接打在控制台。
