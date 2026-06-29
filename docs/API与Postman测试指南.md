# API 与 Postman 测试

## 启动

```powershell
cd deploy
docker compose -f docker-compose.dev.yml up -d

cd ..\backend
go run ./cmd/server
```

配置见 `deploy/.env`（**DB_PORT** 须与 Navicat、后端一致）。

## Postman（自动同步）

**一次性设置**（详见 [postman/README.md](../postman/README.md)）：

1. Postman 桌面版 → Workspace → **Connect to Git** / 关联本地仓库
2. 选择项目根目录 `IHope`
3. Postman 读取 `.postman/resources.yaml`，自动加载 `postman/` 下集合与环境
4. 右上角选 **IHope Local**

之后改 `postman/` 里 yaml 保存即同步，**无需 Import**。

注意：环境变量值**末尾不要多空格/回车**（否则可能 `invalid_json`）。

### 测完重置变量

跑 **0. 健康检查 → Reset environment variables**（发请求前脚本恢复全部默认值，并验证 health）。

Postman 自带 **Reset all** 在 Native Git 下常无效，不要依赖。也不要在 Postman UI 里保存环境（会把空 token 写回 yaml，覆盖 Git 里的初始值）。

| 变量 | 重置后 |
|------|--------|
| `access_token` / `refresh_token` / `reset_token` / `old_*` | 空 |
| `login_password` | `password123` |
| `baseUrl` / `device_id` | 见上表 |

## 测试顺序

| # | 请求 | 期望 |
|---|------|------|
| 1 | GET /api/health | 200 |
| 2 | POST /api/auth/register | 201（已注册 409） |
| 3 | POST /api/auth/login | 200，token 自动写入变量 |
| 4 | GET /api/users/me | 200 |
| 5 | POST /api/auth/refresh | 200，新 token |
| 6 | POST /api/auth/change-password | 200，全部会话作废 |
| 7 | GET /api/users/me (after change) | 401 `session_revoked` |
| 8 | POST /api/auth/login (after change) | 200，新密码 |
| 9 | POST /api/auth/forgot-password | 200，含 `dev_reset_token` |
| 10 | POST /api/auth/reset-password | 200 |
| 11 | GET /api/users/me (after reset) | 401 `session_revoked` |
| 12 | POST /api/auth/login (after reset) | 200，新密码 |

登录/注册 body 示例见集合内各请求。

## 已实现 API

| 方法 | 路径 | 鉴权 |
|------|------|------|
| GET | /api/health | 否 |
| POST | /api/auth/register | 否（限流） |
| POST | /api/auth/login | 否（限流） |
| POST | /api/auth/refresh | 否 |
| POST | /api/auth/forgot-password | 否 |
| POST | /api/auth/reset-password | 否 |
| POST | /api/auth/change-password | Bearer JWT |
| GET | /api/users/me | Bearer JWT |

## 限流

在 `deploy/.env` 修改：

```env
LOGIN_RATE_LIMIT=5
LOGIN_RATE_WINDOW_SEC=60
```

仅 **register / login** 限流，超限 `429`。

## 常见问题

| 现象 | 处理 |
|------|------|
| 连不上库 | Docker 是否运行；`DB_PORT` 是否与 `deploy/.env` 一致 |
| 401 /me | 先 login；access_token 约 15 分钟过期 |
| 429 | 登录太频繁，等 1 分钟 |
| token 未写入变量 | 选 IHope Local；检查 Post-response 脚本 |
| forgot 无 dev_reset_token | 确认 forgot 的 email 与 register 一致；重启后端 |

详细需求见 [需求规格说明书.md](./需求规格说明书.md)，开发路线见 [开发指南.md](./开发指南.md)。
