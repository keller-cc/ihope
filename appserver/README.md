# appserver

Web IM 后端。邮件 / QQ 等读仓库根目录 `deploy/.env`；本目录 `.env` 只覆盖库、端口、Web 域名、JWT。

## 与旧栈隔离

| | 旧 App | Web IM |
|--|--|--|
| Compose | `deploy/docker-compose.dev.yml` | `appserver/docker-compose.yml` |
| 端口 | 5433 · 库 `ihope` | **5434** · 库 **`ihope_web`** |
| HTTP | `:8080` | **`:8090`** |

## 本地运行

```powershell
# 1. 库（首次 copy .env.example .env）
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
- 管理页：http://localhost:5173/admin（`ADMIN_TOKEN`，默认见 `.env.example`）  
- 双账号同浏览器：`?slot=a` / `?slot=b`

启动日志应出现 `config: shared .../deploy/.env` 与 `config: web overlay .env`。

## 说明

邮箱注册与旧 IHope 相同；`MAIL_DRIVER=log` 时验证链接打在控制台。  
QQ / SMTP 用 `deploy/.env`，无需写进 `appserver/.env`。
