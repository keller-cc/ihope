# deploy 目录说明

本目录用于 **本地开发** 与 **生产 Docker 部署** 的环境配置。

| 场景 | Compose 文件 |
|------|----------------|
| 本地开发（仅 PostgreSQL） | `docker-compose.dev.yml` + 宿主机 `go run` |
| 生产 / 一体化验收 | `docker-compose.yml`（postgres + backend + nginx） |

---

## 目录与文件一览

```
deploy/
├── README.md                 # 本说明
├── cloudflared/              # Cloudflare Tunnel（Windows 本地穿透）
│   ├── README.md
│   ├── cloudflared.exe       # 已纳入 Git
│   ├── config.yml
│   └── .cloudflared/         # 凭证 JSON（勿提交）
├── docker-compose.dev.yml    # 本地开发：只启动 PostgreSQL
├── docker-compose.yml        # 生产：postgres + backend + nginx
├── nginx.conf                # 生产 Nginx 反代（REST + WebSocket）
├── nginx-ssl.conf.example    # HTTPS 模板（443 + certbot 路径 + HTTP 跳转）
├── upgrade-dev.ps1           # 开发无感升级脚本
├── .env                      # 本地密钥与端口（勿提交 Git）
└── data/                     # dev compose 数据卷（勿提交 Git）
    └── postgres/
```

| 路径 | 是否提交 Git | 说明 |
|------|--------------|------|
| `docker-compose.dev.yml` | 是 | 开发用 PostgreSQL |
| `docker-compose.yml` | 是 | 生产编排 |
| `nginx.conf` | 是 | 生产反代配置（HTTP 80） |
| `nginx-ssl.conf.example` | 是 | HTTPS 443 模板，复制后改域名与证书路径 |
| `cloudflared/` | 部分 | Tunnel 客户端与配置；`.cloudflared/*.json` 勿提交 |
| `.env` | 否 | 从项目根 `.env.example` 复制 |
| `data/postgres/` | 否 | dev 卷数据，删目录 = 重置库 |

---

## 管理后台（Web）

后端启动后访问 **`http://localhost:8080/admin/`**（静态页在仓库 `admin/`）。

在 `deploy/.env` 配置开发者密钥：

```env
ADMIN_SECRET=your-long-random-dev-secret
```

管理页输入同一密钥即可，**无需 App 用户账号**。详见 [`admin/README.md`](../admin/README.md)。

**Cloudflare Tunnel 内测**（域名 `im.cplprince.top`）时，管理页与 health 走公网：

- `http://im.cplprince.top/admin/`
- `http://im.cplprince.top/api/health`

`deploy/.env` 需设 `APP_PUBLIC_URL=http://im.cplprince.top`、`CORS_ALLOW_ORIGIN=http://im.cplprince.top`。详见 [cloudflared/README.md](./cloudflared/README.md)。

会话相关（`deploy/.env`）：

```env
REFRESH_TOKEN_TTL_DAYS=30
```

超过该天数未 refresh 的设备 token 失效；App 退出会调用 `POST /api/auth/logout` 清除当前设备 token。

---

## 各文件详解

### `docker-compose.dev.yml`

定义 **一个服务**：`postgres`。

- 镜像：`postgres:16-alpine`
- 容器名：`ihope-postgres-dev`
- 读取同目录 `.env` 中的 `DB_PASSWORD`、`POSTGRES_USER`、`POSTGRES_DB`、`DB_PORT`
- 把容器内 `5432` 映射到宿主机 `${DB_PORT}`

**常用命令（在 deploy 目录执行）：**

```powershell
docker compose -f docker-compose.dev.yml up -d      # 后台启动
docker compose -f docker-compose.dev.yml down       # 停止
docker compose -f docker-compose.dev.yml ps         # 状态
docker logs ihope-postgres-dev --tail 30            # 日志
```

---

### `.env`

本地环境变量，主要两类用途：

1. **给 Docker Compose 用** — 创建 PostgreSQL 时的用户、库名、密码、宿主机端口  
2. **给人和后端参考** — Navicat、PowerShell 里 `$env:DB_PASSWORD` 等应与此一致  

| 变量 | 作用 |
|------|------|
| `DB_PASSWORD` | 数据库密码（首次建卷时固定） |
| `POSTGRES_USER` | 数据库用户名，默认 `ihope` |
| `POSTGRES_DB` | 数据库名，默认 `ihope` |
| `DB_HOST` | 本机连接地址，一般 `127.0.0.1` |
| `DB_PORT` | Navicat / 后端连接的端口（映射到 Docker） |
| `JWT_SECRET` | JWT 签名密钥（后端需同名环境变量） |
| `APP_PUBLIC_URL` | 重置密码邮件里的链接前缀 |
| `SERVER_PORT` | 后端 HTTP 端口 |
| `MAIL_DRIVER` | `log` = 开发打印邮件；生产用 `smtp` |
| `SMTP_*` | 生产发信配置 |
| `JPUSH_APP_KEY` / `JPUSH_MASTER_SECRET` | 国内极光推送（可选） |
| `FCM_SERVER_KEY` | 海外 Firebase 推送（可选） |

推送说明见 [docs/推送配置指南.md](../docs/推送配置指南.md)。

### 客户端可见配置（env → `/api/health`）

| 变量 | 作用 |
|------|------|
| `MAX_ENCRYPTED_FILE_BYTES` | IM 附件上限（0=不限，默认 300MB） |
| `CLOUD_DRIVE_URL` | 1t1 网盘地址 |
| `SERVER_VERSION` | 版本号 |
| `DRAIN_SECONDS` | 优雅排空秒数 |

修改后需**重启后端**；管理页可查看，无运行时热更新。

### 开发无感升级

App 固定连 `PUBLIC_PORT`（8080），`go run ../backend/cmd/devproxy` 转发到 `.active-backend-port` 中的后端（8081/8082 交替）。升级执行 `.\upgrade-dev.ps1` 或管理页「排空本实例」。详见上文脚本注释。

首次使用：

```powershell
cd deploy
copy ..\.env.example .env
```

---

### `data/postgres/`

PostgreSQL **数据目录**，由 Docker 挂载生成，**不要手动改里面文件**。

| 内容 | 说明 |
|------|------|
| 表数据 | users、user_devices 等 migration 创建的表 |
| 用户密码 | 首次 `up` 时根据 `.env` 的 `DB_PASSWORD` 初始化 |
| 配置文件 | `postgresql.conf`、`pg_hba.conf` 等，由镜像管理 |

**重置数据库（密码改乱、Navicat 连不上时）：**

```powershell
cd deploy
docker compose -f docker-compose.dev.yml down
Remove-Item -Recurse -Force .\data\postgres
docker compose -f docker-compose.dev.yml up -d
```

---

## 与项目其他目录的关系

```
IHope/
├── .env.example          # 环境变量模板（可提交），复制到 deploy/.env
├── backend/              # Go 后端（连接 DB_HOST:DB_PORT）
├── deploy/               # ← 本目录
└── docs/                 # Windows开发环境.md、API 测试指南等
```

后端连接串由 `backend/internal/config/config.go` 根据环境变量组装：

`postgres://ihope:密码@127.0.0.1:端口/ihope?sslmode=disable`

---

## 生产环境（docker compose）

`docker-compose.yml`：PostgreSQL + Go 后端 + Nginx（默认对外 **80** 端口）。

```powershell
cd deploy
copy ..\.env.example .env
# 编辑 .env：DB_PASSWORD、JWT_SECRET、ADMIN_SECRET、APP_PUBLIC_URL=https://你的域名
docker compose up -d --build
docker compose ps
curl http://localhost/api/health
```

| 服务 | 说明 |
|------|------|
| `postgres` | 数据卷 `postgres_data`，不暴露到公网 |
| `backend` | 镜像自 `backend/Dockerfile`；上传目录卷 `uploads_data` |
| `nginx` | 反代 REST + `/ws`；`client_max_body_size 320m` |

**生产 `.env` 注意：**

- `APP_PUBLIC_URL` 设为公网 HTTPS 地址（App 更新包、邮件链接）
- compose 会将 `DB_HOST` 覆盖为 `postgres`，勿依赖 `127.0.0.1`
- `CORS_ALLOW_ORIGIN` 生产建议填 App/Web 域名，勿用 `*`
- APK 分发：把包放进卷 `uploads_data` 的 `releases/latest.apk`，或设 `APP_DOWNLOAD_URL`
- 可选 `HTTP_PORT=8080` 若 80 已被占用

**HTTPS（直连 VPS，不用 Cloudflare）：** 默认 compose 仅暴露 **80** 端口。在 VPS 上启用 TLS 的推荐步骤：

1. 域名 A 记录指向 VPS，`docker compose up -d` 先跑通 HTTP  
2. 复制模板：`copy nginx-ssl.conf.example nginx-ssl.conf`，将 `im.example.com` 改为你的域名  
3. 用 **certbot** 在宿主机申请证书（不必写进 compose）：

```bash
sudo apt install certbot
sudo certbot certonly --standalone -d im.example.com
# 证书目录：/etc/letsencrypt/live/im.example.com/
```

4. 修改 `docker-compose.yml` 中 nginx 服务（示例）：

```yaml
nginx:
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./nginx-ssl.conf:/etc/nginx/conf.d/default.conf:ro
    - /etc/letsencrypt:/etc/letsencrypt:ro
```

5. `docker compose up -d nginx` 重载。续期：`certbot renew` + 重载 nginx。

也可在**宿主机** Nginx/Caddy 终止 TLS 并反代到 `127.0.0.1:80`，则容器内仍用 `nginx.conf` 即可。

**Cloudflare（橙云 / Tunnel）：** 用户侧 HTTPS 由 Cloudflare 提供，源站可只开 HTTP 或使用 CF Origin Certificate。需开启 **WebSockets**；注意橙云代理 **单文件上传约 100MB 上限**（IM 最大 300MB 见网盘或灰云子域）。详见 [docs/Cloudflare部署指南.md](../docs/Cloudflare部署指南.md)，Nginx 模板 `nginx-cloudflare.conf.example`。

**国内用户、不想备案：** 推荐 **香港 VPS + 域名 A 记录直连 + certbot**，不用 Cloudflare 橙云。逐步说明见 [docs/无备案国内部署指南.md](../docs/无备案国内部署指南.md)（domestic APK + 极光）。

**构建上下文：** 仓库根目录（含 `admin/`）；见根目录 `.dockerignore`。

**发布 APK：**

**方式 A — 本地构建 + 上传到服务器**

```powershell
cd mobile
copy config\prod.json.example config\prod.json   # 填 API_BASE=https://你的域名
.\scripts\build-release.ps1 -Flavor domestic
# 复制到 uploads 卷（容器名 ihope-backend）
docker cp build\app\outputs\flutter-apk\app-domestic-release.apk ihope-backend:/data/uploads/releases/latest.apk
```

App 内「检查版本」会拉取 `uploads/releases/latest.apk`。

**方式 B — GitHub Actions（推荐内测分发）**

1. 仓库 Secrets 设置 **`API_BASE`** = 生产 API 地址（与 `APP_PUBLIC_URL` 一致）
2. **Actions → Release APK → Run workflow**（分支 **main**，指定 tag）
3. 产物出现在 [GitHub Releases](https://github.com/keller-cc/ihope/releases)，用户直接下载 `app-domestic-release.apk`
4. 可选：将 APK `docker cp` 到 `uploads/releases/latest.apk`，或把 Release 直链写入 `APP_DOWNLOAD_URL`

详见 [mobile/README.md](../mobile/README.md)「GitHub Actions 发布」。本地已构建、无 `gh` CLI 时可用 [`scripts/publish-github-release.ps1`](../scripts/publish-github-release.ps1)。

---
