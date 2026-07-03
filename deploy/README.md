# deploy 目录说明

本目录用于 **本地开发与将来生产部署** 的 Docker / 环境配置。  
当前仅包含 **开发用 PostgreSQL**；后端在宿主机用 `go run` 启动。

---

## 目录与文件一览

```
deploy/
├── README.md                 # 本说明
├── docker-compose.dev.yml    # 本地开发：只启动 PostgreSQL
├── .env                      # 本地密钥与端口（勿提交 Git）
└── data/                     # Docker 数据卷（自动生成，勿提交 Git）
    └── postgres/             # PostgreSQL 数据文件（表、用户密码等）
```

| 路径 | 是否提交 Git | 说明 |
|------|--------------|------|
| `docker-compose.dev.yml` | 是 | Compose 编排定义 |
| `.env` | 否 | 从项目根 `.env.example` 复制而来 |
| `data/postgres/` | 否 | 容器运行后自动创建，删目录 = 重置数据库 |

---

## 管理后台（Web）

后端启动后访问 **`http://localhost:8080/admin/`**（静态页在仓库 `admin/`）。

在 `deploy/.env` 配置开发者密钥：

```env
ADMIN_SECRET=your-long-random-dev-secret
```

管理页输入同一密钥即可，**无需 App 用户账号**。详见 [`admin/README.md`](../admin/README.md)。

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

## 生产环境（尚未实现）

开发指南中规划的生产部署还会包含：

- `docker-compose.yml` — postgres + backend + nginx
- `nginx.conf` — HTTPS 反向代理

当前仓库 **只有** `docker-compose.dev.yml`，专用于本地一人开发。
