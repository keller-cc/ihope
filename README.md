# IHope

公司内部轻量 IM（Go 后端 + Flutter，当前完成后端账号体系）。

**Windows 开发机：** 仓库放 `D:\IHope`，环境见 [Windows 开发环境](docs/Windows开发环境.md)。

## 文档

| 文档 | 说明 |
|------|------|
| [Postman 自动同步](postman/README.md) | 关联 Git，免 Import |
| [API 与 Postman 测试](docs/API与Postman测试指南.md) | 启动、测 API |
| [后端说明](backend/README.md) | 目录、限流、命令 |
| [Windows 开发环境](docs/Windows开发环境.md) | 目录布局、启动、排错 |
| [移动端](mobile/README.md) | Flutter API 地址、双模拟器、GitHub Release |
| [开发指南](docs/开发指南.md) | 分阶段路线 |
| [GitHub Releases](https://github.com/keller-cc/ihope/releases) | CI 构建 domestic APK（仓库 Secret `API_BASE`） |
| [推送配置](docs/推送配置指南.md) | 后台通知、极光/FCM、应用内横幅 |
| [无备案国内部署](docs/无备案国内部署指南.md) | 香港 VPS + 域名 + HTTPS |
| [Cloudflare Tunnel 本地穿透](docs/cloudflared本地隧道.md) | 本机 + `docs/cloudflared.exe` + Tunnel |
| [需求规格](docs/需求规格说明书.md) | 完整需求 |

## 快速开始

```powershell
# 1. 数据库
cd deploy
copy ..\.env.example .env    # 首次
docker compose -f docker-compose.dev.yml up -d

# 2. 后端
cd ..\backend
go run ./cmd/server
```

浏览器：<http://localhost:8080/api/health>

Postman：**Connect to Git** 关联本仓库，自动加载 `postman/`（见 [postman/README.md](postman/README.md)）。

## 配置

**全部在 `deploy/.env`**（改完重启后端）：

| 变量 | 说明 |
|------|------|
| `DB_PORT` / `DB_PASSWORD` 等 | 数据库 |
| `JWT_ACCESS_TTL_MIN` | access_token 分钟数 |
| `LOGIN_RATE_LIMIT` / `LOGIN_RATE_WINDOW_SEC` | 注册/登录限流 |
| `RESET_TOKEN_TTL_MIN` | 重置密码 token 分钟数 |
| `CORS_ALLOW_ORIGIN` | 跨域 |

模板：`.env.example`

## License

Private — 公司内部使用
