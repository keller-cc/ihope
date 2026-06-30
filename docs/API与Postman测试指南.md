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
| `peer_user_id` / `conversation_id` | 空 |
| `member_user_id` / `group_epoch` / `message_*_epoch` | 空 |
| `login_password` | `password123` |
| `login_email` / `login_username` | 见当前环境（Local/Alice=alice，Bob=bob） |
| `identity_public_key` | 见当前环境（Alice 与 Local 相同，Bob 独立公钥） |
| `baseUrl` / `ws_base_url` | `http://localhost:8080` / `ws://localhost:8080` |
| `device_id` | `postman-device-1` / `postman-alice` / `postman-bob` |

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
| 13 | GET /api/users | 200，写入 `peer_user_id` |
| 14 | POST /api/conversations (private) | 201，写入 `conversation_id` |
| 15 | POST /api/conversations/{id}/messages | 201 |
| 16 | GET /api/conversations/{id}/messages | 200，含刚发的消息 |

**阶段 4 群聊（双窗口 Alice + Bob）：**

| # | 请求 | 窗口 | 期望 |
|---|------|------|------|
| 17 | POST /api/conversations (group) | Alice | 201，`epoch=0`，写入 `conversation_id` |
| 18 | POST group message (before member change) | Alice | 201 |
| 19 | DELETE /api/conversations/{id}/members/{userId} | Alice 移除 Bob，**或 Bob 窗口自退**（`member_user_id` 留空时会用 `my_user_id`） | 200，`epoch++` |
| 20 | POST /api/conversations/{id}/members | Alice 重新邀请 Bob | 200，`epoch++` |
| 21 | POST group message (after member change) | Alice | 201 |
| 22 | GET messages (epoch filter) | Bob | 200，**仅**含步骤 21 的消息，不含步骤 18 |

**阶段 3 提示：** 需至少两个账号，且 **Alice / Bob 环境各用不同 `identity_public_key`**（注册时写入，之后不可 PATCH 修改）。推荐 **双窗口 + 双环境**（见下）。

## 双人测试：开两个 Postman 窗口

单窗口只有一个 `access_token`，alice / bob 来回 login 很容易搞混。更直观的做法：

### 1. Pull 后确认有三个环境

| 环境 | 用途 |
|------|------|
| **IHope Local** | 单人全流程（默认 alice） |
| **IHope Alice** | 窗口 A：alice，`device_id=postman-alice`，独立公钥 |
| **IHope Bob** | 窗口 B：bob，`device_id=postman-bob`，独立公钥 |

### 2. 开第二个窗口

Postman 桌面版：

- 菜单 **View → New Postman Window**（或 **File → New Postman Window**）
- 快捷键因版本而异，可在命令面板（Ctrl+K）搜 **New Postman Window**

你会得到 **两个独立窗口**，各自可选不同 Environment，**互不影响**。

### 3. 推荐分工

| 窗口 | 右上角环境 | 操作 |
|------|------------|------|
| **A** | IHope Alice | register → login → 建单聊 → 发消息 → WS 连接 |
| **B** | IHope Bob | register → login → GET 会话/消息 → WS 连接 |

两边 **`conversation_id` 要一致**：alice 建单聊后，把 Environment 里的 `conversation_id` 复制到 bob 窗口（或 bob 跑 `GET /api/conversations` 自动看到）。

### 4. WebSocket 双窗口

- **窗口 A**：`ws://localhost:8080/ws?token={{access_token}}`（alice 已 login）
- **窗口 B**：同样 URL（bob 已 login，token 不同）
- 两边都对同一 `conversation_id` 发 `join`
- alice 窗口 `send` 或 REST 发消息 → bob 窗口应收 `message` 事件

### 5. 首次准备（各窗口各跑一遍）

```
register → login
```

Alice 窗口额外：`GET /api/users` → `POST conversations (private)`（peer 填 bob 的 id，或 users 列表里选）

---

## WebSocket 测试与加密说明

| 层级 | Postman（API 测试） | Flutter 客户端 |
|------|---------------------|----------------|
| 传输 | 本地 `ws://`（无 TLS） | 同左；生产用 `wss://` |
| 消息字段 `ciphertext` | **可填明文**（测存取/推送） | 单聊 `e2ee:v1:`；群聊 `e2ee:g:v1:` |
| `identity_public_key` | 注册时写入，32 字节 Base64 | 每账号独立，注册时上传 |
| 群 welcome | `key_relay` 发 opaque 密文（Postman 用占位符） | 客户端 ECDH 加密 GMK |

Postman 里 `ciphertext` 直接填可读文字即可，用于验证 REST/WS 链路；**不是** Flutter E2EE 行为。

### 集合内 WebSocket 请求（Pull 后）

| 请求 | 环境 / 窗口 | Saved messages |
|------|-------------|----------------|
| **WS Alice join and send** | IHope Alice | 1 join → 2 send → 3 key_relay（可选） |
| **WS Alice key_relay** | IHope Alice | 1 join → 2 key_relay |
| **WS Bob join (listen)** | IHope Bob | 1 join |

**推荐顺序：**

1. REST 准备好：`conversation_id`（Alice 建单聊）  
2. **Bob 窗口**：打开 `WS Bob join (listen)` → **Connect** → Send **1 join** → 等 `joined`  
3. **Alice 窗口**：打开 `WS Alice join and send` → **Connect** → Send **1 join** → **2 send**  
4. Alice 收 `sent`；Bob 收 `message`（含 `sender_id`、明文 `ciphertext`）

连接 URL：`{{ws_base_url}}/ws?token={{access_token}}`

手动 JSON 示例：

```json
{"event":"join","conversation_id":"{{conversation_id}}"}
{"event":"send","conversation_id":"{{conversation_id}}","type":"text","ciphertext":"hi"}
{"event":"key_relay","conversation_id":"{{conversation_id}}","target_user_id":"{{member_user_id}}","payload_type":"welcome_bundle","ciphertext":"opaque-ciphertext"}
```

| 方向 | event | 说明 |
|------|-------|------|
| C→S | join / send / key_relay | 订阅会话 / 发消息 / 中转 welcome 密文 |
| S→C | joined / sent / message / relayed / key_relay / epoch_updated / error | 响应与推送 |

登录/注册使用 `login_email` / `login_username` / `login_password`。

## 已实现 API

| 方法 | 路径 | 鉴权 |
|------|------|------|
| GET | /api/health | 否 |
| POST | /api/auth/register | 否（限流；须带合法 `identity_public_key`） |
| POST | /api/auth/login | 否（限流） |
| POST | /api/auth/refresh | 否 |
| POST | /api/auth/forgot-password | 否 |
| POST | /api/auth/reset-password | 否 |
| POST | /api/auth/change-password | Bearer JWT |
| GET | /api/users/me | Bearer JWT |
| GET | /api/users | Bearer JWT |
| GET | /api/conversations | Bearer JWT |
| POST | /api/conversations | Bearer JWT |
| POST | /api/conversations/{id}/members | Bearer JWT（群主邀请） |
| DELETE | /api/conversations/{id}/members/{userId} | Bearer JWT（群主移除或自退） |
| GET | /api/conversations/{id}/messages | Bearer JWT |
| POST | /api/conversations/{id}/messages | Bearer JWT |
| GET | /ws | JWT（query `token` 或 Bearer） |

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
