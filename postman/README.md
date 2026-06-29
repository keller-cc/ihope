# Postman 自动同步

集合与环境以 **`postman/`** 目录为唯一来源，通过 Postman **Native Git** 与仓库自动同步，无需手动 Import JSON。

## 一次性设置

1. 安装 [Postman 桌面版](https://www.postman.com/downloads/)（需较新版本，支持 Native Git）
2. 打开 Postman → 左上角 **Workspaces** → 你的 Workspace
3. **Add repository** / **Connect to Git**（或 Settings → 关联本地 Git 仓库）
4. 选择本仓库根目录：`D:\施玮书房\IHope`
5. Postman 会读取 `.postman/resources.yaml`，自动加载：
   - 集合：`postman/collections/IHope API/`
   - 环境：`postman/environments/IHope.environment.yaml`
6. 右上角 Environment 选 **IHope Local**

## 日常使用

- 改 `postman/` 下 yaml 并保存 → Postman 自动更新
- 在 Postman 里改请求并保存 → 写回 yaml（可提交 Git）

## 目录

```
postman/
├── collections/IHope API/     # API 请求（*.request.yaml）
└── environments/              # IHope Local 环境变量
```

## 注意

- **不要** Import 或映射 `docs/postman/*.json`（已停用，见 [docs/postman/README.md](../docs/postman/README.md)）
- Workspace 里若同时出现 **IHope API** 和 **IHope.postman_collection.json`，删除 JSON 那份，并检查 `.postman/resources.yaml` 是否误加了 json 路径
- 环境只保留 **IHope**（来自 `IHope.environment.yaml`），不要勾选两份环境
- 环境变量值末尾不要多空格/回车（会导致 `invalid_json`）
- 登录后 token 写入 **Environment**（不再写 Collection 变量）

**测完重置变量：** 跑 **0. 健康检查 → Reset environment variables**（推荐）。

Postman 自带的 Environment → **Reset all** 在 **Native Git** 下经常无效（空 token 的 Shared 值无法正确同步，且 Postman 保存环境时可能把空值写回 yaml）。Reset 请求会在发请求前把变量设回默认值，并顺带检查 `/api/health`。

| 变量 | 重置后 |
|------|--------|
| `access_token` / `refresh_token` / `reset_token` / `old_*` | 空 |
| `login_password` | `password123` |
| `baseUrl` | `http://localhost:8080` |
| `device_id` | `postman-device-1` |

**勿在 Postman 里直接改环境并保存**（容易把 yaml 里初始值覆盖成空）；改默认值请编辑 `postman/environments/IHope.environment.yaml` 后 Pull。

## 在 Postman 里改了会同步到代码吗？

**会**（仅限 Native Git 关联的 **IHope API** 集合）：

- 在 Postman 改请求 URL、Body、脚本等 → 保存 → 对应 `postman/collections/IHope API/**/*.request.yaml` 会更新
- 改环境变量 → `postman/environments/IHope.environment.yaml` 会更新
- 改完后可在 Cursor 里看到文件变化，可 `git commit`

**不会**同步到代码的情况：

- 改的是 **IHope.postman_collection.json**（手动 Import 的旧集合）
- 改的是云端未关联 Git 的集合

建议：删除 Workspace 里的 `IHope.postman_collection.json` 集合，只用 **IHope API**。

## 集合显示为空？

Git 里 `postman/collections/IHope API/` 有文件，但 Postman 侧边栏空白，按顺序排查：

1. **切到 Local View**（Native Git 必须；Cloud View 可能空白）
2. **Pull / Sync**：从仓库拉最新 yaml（含本次 folder 修复）
3. **确认打开的是 Git 关联 Workspace**，仓库根目录为 `D:\施玮书房\IHope`
4. **子文件夹必须是 `$kind: folder`**（不是 `collection`）；根目录 `.resources/definition.yaml` 才是 `$kind: collection`
5. 删除手动 Import 的旧 JSON 集合，避免看错集合
6. 集合名应显示 **IHope API**，展开后应有 0–4 五个文件夹

仍为空：Postman 设置里对该仓库 **Disconnect 再 Connect**，或升级 Postman 到 v12+。

## WebSocket 请求不显示？

Postman v3 对 **文件名** 很敏感。请使用与 HTTP 请求相同的命名风格（`METHOD -path-segments.request.yaml`），**不要**在文件名里用多个空格或特殊符号（如 `—`、`&`）。

| 正确 | 错误（可能被 Postman 忽略） |
|------|---------------------------|
| `WS -ws-alice-join-and-send.request.yaml` | `WS - alice join and send.request.yaml` |

WebSocket 请求与 Saved messages 的正确结构（以 Postman 写回的 `example22` 为准）：

```
4. 会话与消息/
├── WS -ws-alice-join-and-send.request.yaml   # messages: .resources/WS -ws-alice-join-and-send.resources/messages
├── WS -ws-bob-join.request.yaml
└── .resources/
    ├── definition.yaml
    ├── WS -ws-alice-join-and-send.resources/messages/*.message.yaml
    └── WS -ws-bob-join.resources/messages/*.message.yaml
```

**不要**在 `.request.yaml` 里内联 `messages:` 数组（Postman 会忽略整个请求）。消息文件扩展名必须是 **`.message.yaml`**，字段为 `content` + `contentType`（`json` 或 `text`）。

WebSocket 需 **Postman v12+** 且 **Local View**；混在同一 HTTP 集合里在 Native Git 下才支持。
