# Windows 开发环境 + GitHub 工作流

一人开发、开发机 Windows、代码托管 GitHub 的完整说明。

---

## 1. 软件安装清单

| 软件 | 用途 | 安装后验证 |
|------|------|------------|
| **Git for Windows** | 版本管理、推 GitHub | `git --version` |
| **Go 1.22+** | 后端 | `go version` |
| **Docker Desktop** | 本地 PostgreSQL | `docker compose version` |
| **Flutter SDK** | Android/iOS App | `flutter doctor` |
| **Android Studio** | 模拟器、SDK | 打开 AVD Manager |
| **VS Code** 或 **Cursor** | 编辑 | — |
| **GitHub CLI**（可选） | 命令行建仓库 | `gh auth status` |

### Flutter on Windows 注意

```powershell
flutter doctor
```

需解决：

- Android toolchain（装 Android Studio + SDK）
- Android licenses：`flutter doctor --android-licenses`
- iOS 无法在 Windows 上编译，需 Mac 或 CI 云构建 / 真机远程打包

**一人开发建议：** 先在 Windows 上完成 **Android 模拟器 + 真机** 调试；iOS 后期借 Mac 或 TestFlight 流水线。

---

## 2. 项目首次拉取 / 初始化

```powershell
cd "D:\施玮书房\IHope"

# 数据库环境变量（必须在 deploy 目录，勿提交）
cd deploy
copy ..\.env.example .env
docker compose -f docker-compose.dev.yml up -d
cd ..

# 后端
cd backend
go mod download
go run ./cmd/server
# 自动加载 ../deploy/.env，控制台应看到：config: loaded ../deploy/.env
```

另开 PowerShell 窗口验证：

```powershell
curl http://localhost:8080/api/health
```

---

## 3. Windows 日常开发命令

### 3.1 启动数据库（开机后一次）

**必须在 `deploy` 目录执行**，Compose 才会加载 `deploy/.env`。

```powershell
cd D:\施玮书房\IHope\deploy
copy ..\.env.example .env   # 首次；.env 已存在则跳过
docker compose -f docker-compose.dev.yml up -d
```

确认运行中：

```powershell
docker ps --filter name=ihope-postgres-dev
docker compose -f docker-compose.dev.yml ps
```

#### Navicat 连接参数

| 字段 | 值 |
|------|-----|
| 连接类型 | PostgreSQL |
| 主机 | `127.0.0.1` |
| 端口 | `5432`（与 `deploy/.env` 中 `DB_PORT` 一致，可自行修改） |
| 初始数据库 | `ihope` |
| 用户名 | `ihope` |
| 密码 | `deploy/.env` 里 `DB_PASSWORD`（默认 `devpassword`） |
| SSL | 关闭 |

连接字符串：`postgres://ihope:devpassword@127.0.0.1:5432/ihope?sslmode=disable`

容器内验证：

```powershell
docker exec -it ihope-postgres-dev psql -U ihope -d ihope -c "SELECT 1;"
```

#### Navicat 连不上

1. **端口不一致**：Navicat 端口须与 `deploy/.env` 的 `DB_PORT` 相同（默认 `5432`）。
2. **密码与数据卷不一致**：PostgreSQL 密码在首次建库时固定；改 `.env` 后需重建数据卷：

```powershell
cd D:\施玮书房\IHope\deploy
docker compose -f docker-compose.dev.yml down
Remove-Item -Recurse -Force .\data\postgres -ErrorAction SilentlyContinue
docker compose -f docker-compose.dev.yml up -d
```

3. **容器未跑**：先启动 Docker Desktop，再 `docker compose ... up -d`。
4. **主机填错**：用 `127.0.0.1`，不要用容器名 `ihope-postgres-dev`。

### 3.2 启动后端（开发窗口 1）

在 `backend` 目录执行即可，**会自动读取 `../deploy/.env`**（无需再手动 `$env:DB_*`）。

```powershell
cd D:\施玮书房\IHope\backend
go run ./cmd/server
```

启动日志应包含：

```
config: loaded ../deploy/.env
database migrations applied
server listening on http://localhost:8080
```

若需指定其他 env 文件：`$env:ENV_FILE="D:\path\to\.env"; go run ./cmd/server`

### 3.2.1 运行 Go 测试

```powershell
cd D:\施玮书房\IHope\backend

# 全部测试（单元 + 集成）
go test ./... -count=1 -v
```

**Docker 端口 5433 时：** 确保 `deploy/.env` 里 `DB_PORT=5433`，且容器已启动。测试会自动向上查找 `deploy/.env`（与 `go run` 一致）。

若仍出现 `SKIP: database not available` 且连的是 **5432**，可显式指定：

```powershell
$env:TEST_DATABASE_URL = "postgres://ihope:devpassword@127.0.0.1:5433/ihope?sslmode=disable"
go test ./... -count=1 -v
```

密码以 `deploy/.env` 的 `DB_PASSWORD` 为准。详见 [开发指南.md §12](./开发指南.md#12-测试建议)。

**提示：** 可把环境变量写入项目根 `.env`，用 [godotenv](https://github.com/joho/godotenv) 加载，或 Windows 用户环境变量里配置。

### 3.3 启动 Flutter（开发窗口 2）

```powershell
cd D:\施玮书房\IHope\mobile
flutter pub get
flutter run
```

### 3.4 Android 模拟器访问本机后端

| 场景 | API 基地址 |
|------|------------|
| Android 模拟器 | `http://10.0.2.2:8080` |
| Windows 本机浏览器/curl | `http://localhost:8080` |
| 同一 WiFi 真机 | `http://<电脑局域网IP>:8080` |

查局域网 IP：

```powershell
ipconfig
# 看「无线局域网适配器 WLAN」的 IPv4，如 192.168.1.10
```

真机调试时 Windows 防火墙可能拦截 8080，需允许入站或临时关闭防火墙测试。

---

## 4. 提交到 GitHub

### 4.1 首次推送

**方式 A：网页 + HTTPS（简单）**

1. 登录 [GitHub](https://github.com) → New repository  
2. 名称如 `ihope`，选 **Private**，**不要**勾选 Add README  
3. 本地执行：

```powershell
cd "D:\施玮书房\IHope"

git init
git add .
git status   # 确认没有 .env、deploy/data/ 等被加入
git commit -m "chore: initial scaffold — Go backend, docs, Docker dev"
git branch -M main
git remote add origin https://github.com/<用户名>/ihope.git
git push -u origin main
```

推送时 GitHub 会要求登录，可用 **Personal Access Token** 代替密码：  
Settings → Developer settings → Personal access tokens → Generate (repo 权限)。

**方式 B：GitHub CLI**

```powershell
gh auth login
gh repo create ihope --private --source=. --remote=origin --push
```

### 4.2 切勿提交的内容

已在 `.gitignore` 中排除：

- `.env`（含 DB 密码、JWT_SECRET、SMTP 密码）
- `deploy/data/`（PostgreSQL 数据）
- `mobile/build/`、签名密钥 `*.jks`
- IDE 私有配置

推送前习惯检查：

```powershell
git status
git diff --staged
```

### 4.3 一人开发分支策略（简单够用）

```
main      稳定、可部署；功能完成再合并
develop   日常开发（可选；一人也可只用 main + feature 分支）
feature/* 单功能，如 feature/auth-email
```

推荐流程：

```powershell
git checkout -b feature/auth-email
# ... 开发 ...
git add backend/internal/auth
git commit -m "feat(auth): add email register and forgot password"
git checkout main
git merge feature/auth-email
git push origin main
```

一人项目 **不必** 强行走 PR，但 **commit 小步、信息清楚** 便于以后查。

### 4.4 GitHub Actions

推送 `main` 后自动跑 `.github/workflows/ci.yml`：

- `go vet`、`go build` 后端  
- Flutter 在 `mobile/` 用 `flutter create` 初始化后，取消 workflow 里 mobile  job 注释  

---

## 5. GitHub Secrets（上线部署时用）

Repository → Settings → Secrets and variables → Actions：

| Secret | 说明 |
|--------|------|
| `VPS_HOST` | 境外服务器 IP |
| `VPS_SSH_KEY` | 部署用 SSH 私钥 |
| `DB_PASSWORD` | 生产数据库密码 |
| `JWT_SECRET` | 生产 JWT |
| `SMTP_PASS` | 邮件服务密码 |

**开发阶段不需要配**；本地用 `.env` 即可。

---

## 6. 一人开发节奏（Windows 每周）

| 周 | 目标 | 产出 |
|----|------|------|
| 1 | Auth + Docker + GitHub | 注册/登录 API，仓库已 push |
| 2 | 邮箱找回密码 | forgot/reset 可用，邮件 log 模式 |
| 3 | 消息 REST + WSS 明文 | Postman + 简单 Flutter 聊天 |
| 4+ | 见 [开发指南.md](./开发指南.md) | E2EE、群聊、多设备 |

**每天结束：**

```powershell
git add .
git commit -m "描述今天做了什么"
git push
```

备份在 GitHub，换电脑只需 `git clone`。

---

## 7. 换电脑 / 新环境恢复

```powershell
git clone https://github.com/<用户名>/ihope.git
cd ihope

cd deploy
copy ..\.env.example .env
docker compose -f docker-compose.dev.yml up -d

cd ..\backend
go mod download
go run ./cmd/server
```

---

## 8. 常见问题（Windows）

### Docker 启动失败

- 确认 Docker Desktop 已运行（系统托盘鲸鱼图标）
- WSL2：Docker Desktop → Settings → 启用 WSL2 backend

### `go: command not found`

- 重装 Go，安装时勾选 Add to PATH  
- 新开 PowerShell 再试

### Flutter 找不到 Android SDK

```powershell
flutter config --android-sdk "C:\Users\<你>\AppData\Local\Android\Sdk"
flutter doctor
```

### Git 中文路径乱码

```powershell
git config --global core.quotepath false
```

### Navicat 无法连接 PostgreSQL

见 [3.1 启动数据库](#31-启动数据库开机后一次) 中「Navicat 连不上」四条排查。

### 端口 5432 / 8080 被占用

```powershell
netstat -ano | findstr :8080
taskkill /PID <pid> /F
```

或改 `SERVER_PORT`、`docker-compose` 端口映射。

---

## 9. 推荐 VS Code / Cursor 扩展

- Go (Google)
- Dart / Flutter
- Docker
- GitLens（可选）

`/.vscode/launch.json` 示例（可选，便于 F5 调试后端）：

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Backend",
      "type": "go",
      "request": "launch",
      "mode": "auto",
      "program": "${workspaceFolder}/backend/cmd/server",
      "env": {
        "DB_PASSWORD": "devpassword",
        "POSTGRES_USER": "ihope",
        "POSTGRES_DB": "ihope",
        "DB_HOST": "127.0.0.1",
        "DB_PORT": "5432",
        "JWT_SECRET": "dev-only-change-in-production-min-32-chars",
        "MAIL_DRIVER": "log"
      }
    }
  ]
}
```

---

## 10. 修订记录

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.2 | 2026-06-29 | 补充 Navicat 连接说明与 DB_PORT 配置 |
| v1.1 | 2026-06-29 | 统一本地 DB 密码说明，补充 Navicat 连接与排查 |
| v1.0 | 2026-06-29 | Windows 单人开发 + GitHub 初版 |
