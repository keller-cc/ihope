# IHope 后端

Go 1.22+ REST API，当前实现阶段 1 账号体系 + 阶段 2 会话与消息（明文版）。

## 启动

```powershell
cd deploy
docker compose -f docker-compose.dev.yml up -d

cd ..\backend
go run ./cmd/server
```

## 配置

**所有可调项在 `deploy/.env`**，后端启动时自动加载。

| 变量 | 默认 | 说明 |
|------|------|------|
| `DB_*` | 见 .env.example | 数据库连接 |
| `JWT_SECRET` | — | JWT 密钥（≥32 字符） |
| `JWT_ACCESS_TTL_MIN` | 15 | access_token 有效期（分钟） |
| `LOGIN_RATE_LIMIT` | 5 | 注册/登录限流次数 |
| `LOGIN_RATE_WINDOW_SEC` | 60 | 限流窗口（秒） |
| `RESET_TOKEN_TTL_MIN` | 30 | 找回密码 token 有效期（分钟） |
| `CORS_ALLOW_ORIGIN` | * | 跨域来源 |
| `MAIL_*` | log | 邮件 |

代码读取：`internal/config/config.go`

## 测试

**不需要先 `go run` 启动服务**；集成测试用内存 HTTP 直接调路由，但 **需要 PostgreSQL**（与 `deploy/.env` 相同配置）。

### 前置

```powershell
cd deploy
docker compose -f docker-compose.dev.yml up -d
```

确认 `deploy/.env` 里 `DB_PORT` 等与 Navicat / Docker 一致。

### 跑全部测试

```powershell
cd backend
go test ./... -count=1 -v
```

### 只跑账号集成测试（对应 Postman 流程）

```powershell
cd backend
go test ./internal/server/... -count=1 -v -run Integration
```

| 测试 | 对应 Postman |
|------|----------------|
| `TestAuthFlowIntegration` | 注册 → 登录 → /me → refresh → forgot |
| `TestResetPasswordFlowIntegration` | 找回密码 → reset → 旧 token 失效 → 新密码登录 |
| `TestChangePasswordFlowIntegration` | 修改密码 → 旧 token 失效 → 新密码登录 |

### 只跑会话集成测试

```powershell
go test ./internal/server/... -count=1 -v -run Conversation
```

| 测试 | 对应 Postman |
|------|----------------|
| `TestConversationFlowIntegration` | 用户列表 → 单聊 → 发消息 → 拉历史 → 建群 |

### 只跑单元测试（无需数据库）

```powershell
go test ./internal/jwt/... ./internal/auth/... ./internal/httpx/... ./internal/middleware/... ./internal/mail/... -count=1 -v
```

### 数据库连不上时

集成测试会 **Skip**（不会 Fail），输出类似 `database not available: ...`。单元测试仍会通过。

可显式指定连接串：

```powershell
$env:TEST_DATABASE_URL="postgres://ihope:devpassword@127.0.0.1:5433/ihope?sslmode=disable"
go test ./internal/server/... -v -run Integration
```

（端口按你的 `deploy/.env` 修改。）

## 常用命令

```powershell
go run ./cmd/server
go test ./...
```

Postman 见 [docs/API与Postman测试指南.md](../docs/API与Postman测试指南.md)。
