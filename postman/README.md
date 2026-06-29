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

- **不要**再 Import `docs/postman/*.json`（会与 Native Git 集合重复）
- Workspace 里若同时出现 **IHope API** 和 **IHope.postman_collection.json**，只保留 **IHope API**，删除 JSON 那份
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
