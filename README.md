# IHope

公司内部轻量即时通讯：单聊/群聊、图片文件、E2EE、多设备同步。  
约 100 人规模，部署于境外云公网。

## 文档

| 文档 | 说明 |
|------|------|
| [需求规格说明书](docs/需求规格说明书.md) | 功能、安全、接口、数据模型 |
| [开发指南](docs/开发指南.md) | 分阶段开发路线 |
| [Windows 开发环境](docs/Windows开发环境.md) | **Windows 单机 + GitHub 工作流** |

## 仓库结构

```
├── backend/          Go 后端
├── mobile/           Flutter App（需 flutter create 初始化）
├── deploy/           Docker Compose（本地 PostgreSQL）
├── docs/             文档
└── .github/workflows CI
```

## 快速开始（Windows）

### 1. 安装依赖

- [Go 1.22+](https://go.dev/dl/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- [Flutter](https://docs.flutter.dev/get-started/install/windows)（做 App 时）
- [Git](https://git-scm.com/download/win)

### 2. 启动数据库

```powershell
cd deploy
copy ..\.env.example .env
# 编辑 .env 中的 DB_PASSWORD（可选，默认 devpassword 即可本地用）
docker compose -f docker-compose.dev.yml up -d
```

### 3. 启动后端

```powershell
cd backend
$env:DB_PASSWORD="devpassword"
$env:JWT_SECRET="dev-only-change-in-production-min-32-chars"
go mod download
go run ./cmd/server
```

浏览器访问：<http://localhost:8080/api/health>

### 4. 初始化 Flutter（可选）

```powershell
cd mobile
flutter create --org com.ihope --project-name ihope .
flutter pub add dio web_socket_channel flutter_secure_storage
flutter run
```

## 提交到 GitHub

```powershell
cd "D:\施玮书房\IHope"
git init
git add .
git commit -m "chore: initial project scaffold for Windows solo dev"
```

在 GitHub 新建空仓库（不要勾选 README），然后：

```powershell
git remote add origin https://github.com/<你的用户名>/ihope.git
git branch -M main
git push -u origin main
```

详细说明（SSH、分支策略、Secrets）见 [docs/Windows开发环境.md](docs/Windows开发环境.md)。

## 技术栈

- **后端**：Go、PostgreSQL、WebSocket
- **移动端**：Flutter
- **部署**：Docker、Nginx、境外 VPS

## License

Private — 公司内部使用
