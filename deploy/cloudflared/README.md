# Cloudflare Tunnel 本地穿透（Windows）

在 **尚无 VPS** 或 **本机开发** 时，用 Cloudflare Tunnel 把 `im.你的域名` 指到本机 `8080`，外网可访问 IHope 后端。

本项目域名：**`clprince.top`**，IM API 子域：**`im.clprince.top`**（Cloudflare NS 已接入）。

## 目录

| 文件 | 是否提交 Git | 说明 |
|------|--------------|------|
| `cloudflared.exe` | 是 | Windows 64-bit 客户端（仓库内自带） |
| `config.yml` | 是 | Tunnel 入口与 hostname（本项目已配置） |
| `config.yml.example` | 是 | 配置模板（换 tunnel 时参考） |
| `.cloudflared/*.json` | 否 | Tunnel 凭证，**切勿提交** |

---

## 架构

### 单后端（简单内测）

```
App / 浏览器 → im.clprince.top → cloudflared → 127.0.0.1:8080 → go run ./cmd/server
```

### 无感升级（devproxy）

```
App → im.clprince.top → cloudflared → 127.0.0.1:8080 → devproxy → 8081 或 8082
```

Tunnel **始终**连 `127.0.0.1:8080`；升级时只换 8081/8082，**不改** `config.yml`。见下文「无感升级」。

---

## 一、Cloudflare 控制台（一次性）

1. [Zero Trust](https://one.dash.cloudflare.com/) → **Networks → Tunnels** → 创建 Tunnel（如 `mytunnel`）
2. 下载凭证 JSON（形如 `xxxxxxxx.json`）
3. **Public Hostname**：`im.clprince.top` → Service `http://127.0.0.1:8080`（网页配置与本地 `config.yml` 二选一或保持一致）
4. 域名 NS 已在 Cloudflare 时，Tunnel 会自动写 DNS
5. **Network → WebSockets → ON**（聊天 WebSocket 需要）

---

## 二、本机准备

```powershell
cd D:\IHope\deploy\cloudflared

# 凭证（勿提交 Git）
mkdir .cloudflared -Force
copy D:\cloudflared\mytunnel.json .cloudflared\mytunnel.json
# 或把 Zero Trust 下载的 json 复制为 deploy\cloudflared\.cloudflared\mytunnel.json
```

`config.yml` 已指向 `im.clprince.top` 与 `127.0.0.1:8080`。

**务必使用 `127.0.0.1`，不要用 `localhost`**，否则 Windows 上可能出现 `dial tcp [::1]:8080 ... refused`。

`deploy/.env` 建议：

```env
APP_PUBLIC_URL=http://im.clprince.top
CORS_ALLOW_ORIGIN=http://im.clprince.top
ADMIN_SECRET=至少32字符的随机串
```

---

## 三、每次启动（单后端）

按顺序开 **3～4 个** PowerShell 窗口：

**窗口 1 — 数据库**

```powershell
cd D:\IHope\deploy
docker compose -f docker-compose.dev.yml up -d
```

**窗口 2 — 后端（占 8080）**

```powershell
cd D:\IHope\backend
go run ./cmd/server
```

**窗口 3 — Tunnel**

```powershell
cd D:\IHope\deploy\cloudflared
.\cloudflared.exe tunnel --config config.yml run
```

**验证**

```powershell
curl http://127.0.0.1:8080/api/health
curl http://im.clprince.top/api/health
```

管理页：`http://im.clprince.top/admin/`（密钥 = `ADMIN_SECRET`）

App：**个人资料 → 服务器** → `http://im.clprince.top`

---

## 四、无感升级（devproxy + upgrade-dev.ps1）

Tunnel **不变**，仍指向 `127.0.0.1:8080`。

**首次额外准备：**

```powershell
# deploy/.env 增加
# BACKEND_PORT_A=8081
# BACKEND_PORT_B=8082

Set-Content D:\IHope\deploy\.active-backend-port -Value "8081" -NoNewline
```

**窗口 2 改为 devproxy（占 8080）：**

```powershell
cd D:\IHope\deploy
go run ../backend/cmd/devproxy
```

**窗口 3 后端在 8081：**

```powershell
cd D:\IHope\backend
$env:SERVER_PORT="8081"
$env:ENV_FILE="D:\IHope\deploy\.env"
go run ./cmd/server
```

**改代码后升级（一条命令）：**

```powershell
cd D:\IHope\deploy
.\upgrade-dev.ps1
```

脚本会在 8082 起新后端 → 切换 `.active-backend-port` → 排空旧 8081。**无需改 Tunnel 或 `config.yml`。**

### 电脑重启后（无感模式）

devproxy 与 Tunnel 仍占 **8080**；后端端口看 `.active-backend-port`：

```powershell
# 窗口3：后端（8081 或 8082）
$port = (Get-Content D:\IHope\deploy\.active-backend-port -Raw).Trim()
if (-not $port) { $port = "8081" }
cd D:\IHope\backend
$env:ENV_FILE="D:\IHope\deploy\.env"
$env:SERVER_PORT=$port
go run ./cmd/server
```

---

## 五、常用命令

```powershell
cd D:\IHope\deploy\cloudflared

# 前台运行（调试）
.\cloudflared.exe tunnel --config config.yml run

# 查看 tunnel 列表
.\cloudflared.exe tunnel list

# 安装为 Windows 服务（可选，开机自启）
.\cloudflared.exe service install
# 需先把 config 路径写入服务配置，见 Cloudflare 文档
```

---

## 六、故障排查

| 现象 | 处理 |
|------|------|
| `refused [::1]:8080` | `config.yml` 改为 `http://127.0.0.1:8080`；确认后端或 devproxy 已启动 |
| 本机 health 通、域名不通 | 先开后端再开 cloudflared；检查 Zero Trust Public Hostname |
| `argotunnel.com i/o timeout` | 网络到 Cloudflare 不稳定，换网或重试 |
| App 聊天断 | Cloudflare 开 WebSockets |
| 升级后全挂 | 确认 devproxy 在 8080 运行，且 `.active-backend-port` 指向存活后端 |

---

## 七、与安全相关

- `deploy/cloudflared/.cloudflared/*.json` 等同密钥，**不要提交 Git**
- 内测可用 HTTP；正式 Release APK 建议 VPS + HTTPS

更多 VPS 部署见 [无备案国内部署指南.md](../../docs/无备案国内部署指南.md)；Cloudflare 橙云/VPS 方案见 [Cloudflare部署指南.md](../../docs/Cloudflare部署指南.md)。

---

## 八、两台电脑各用一套 Tunnel（不共用凭证）

**原则：** 一个 Tunnel = 一份凭证 JSON + 一个（或多个）Public Hostname。**不要**把同一份 `mytunnel.json` 拷到两台电脑同时跑——域名会抢连接，行为不可控。

推荐：**子域名分开**，例如：

| 电脑 | Tunnel 名（示例） | 公网域名 | 凭证文件 |
|------|-------------------|----------|----------|
| A（主） | `mytunnel` | `im.clprince.top` | `.cloudflared/mytunnel.json` |
| B（副） | `mytunnel-b` | `dev-im.clprince.top` | `.cloudflared/mytunnel-b.json` |

### Cloudflare 控制台（电脑 B 一次性）

1. Zero Trust → **Networks → Tunnels** → **Create a tunnel**（新建，不要复用 A 的）
2. 起名如 `mytunnel-b`，下载 **另一份** JSON
3. **Public Hostname** 添加：`dev-im.clprince.top` → `http://127.0.0.1:8080`（子域名可自定，与 A 不同即可）
4. WebSockets 保持 **ON**

### 电脑 B 本机

```powershell
cd D:\IHope\deploy\cloudflared

# 第二套凭证
mkdir .cloudflared -Force
copy \\A电脑或U盘\mytunnel-b.json .cloudflared\mytunnel-b.json

# 第二套 config（勿提交 Git）
copy config.local.yml.example config.local.yml
# 编辑 hostname / tunnel 名 / credentials 路径，与控制台一致

# deploy/.env 改为 B 的域名
# APP_PUBLIC_URL=http://dev-im.clprince.top
# CORS_ALLOW_ORIGIN=http://dev-im.clprince.top
```

启动 Tunnel（注意 `--config`）：

```powershell
cd D:\IHope\deploy\cloudflared
.\cloudflared.exe tunnel --config config.local.yml run
```

电脑 A 仍用默认：

```powershell
.\cloudflared.exe tunnel --config config.yml run
```

### App / Release

- 连 A：`http://im.clprince.top`
- 连 B：`http://dev-im.clprince.top`（个人资料 → 服务器，或单独打 APK / 改 `prod.json`）

两套环境 **数据库、`.env`、后端数据互不影响**（各自本机 Docker + 本机 `deploy/.env`），除非你把 B 的 `DB_HOST` 指到 A（一般不需要）。
