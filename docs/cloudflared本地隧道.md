# Cloudflare Tunnel 本地穿透（Windows）

在 **尚无 VPS** 或 **本机开发** 时，用 Cloudflare Tunnel 把 `im.你的域名.com` 指到本机 `8080`，外网可访问 IHope 后端。

仓库内文件（`docs/` 目录）：

| 文件 | 是否提交 Git | 说明 |
|------|--------------|------|
| `cloudflared.exe` | 否（`*.exe` 已忽略） | 自行放置或从 [Cloudflare 下载](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/) |
| `config.yml.example` | 是 | 配置模板 |
| `config.yml` | 否 | 本地复制模板后修改 |
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
3. **Public Hostname**：`im.你的域名.com` → Service `http://127.0.0.1:8080`（网页配置与本地 `config.yml` 二选一或保持一致）
4. 域名 NS 已在 Cloudflare 时，Tunnel 会自动写 DNS
5. **Network → WebSockets → ON**（聊天 WebSocket 需要）

---

## 二、本机准备

在 `D:\IHope\docs` 下：

```powershell
cd D:\IHope\docs

# 1. 若没有 cloudflared.exe，从官网下载 64-bit Windows 版放到本目录

# 2. 配置
copy config.yml.example config.yml
# 编辑 config.yml：tunnel 名、hostname、credentials 路径

# 3. 凭证（勿提交 Git）
mkdir .cloudflared -Force
copy D:\cloudflared\mytunnel.json .cloudflared\mytunnel.json
# 或把 Zero Trust 下载的 json 复制为 docs\.cloudflared\mytunnel.json
```

`config.yml` 示例（请把域名改成你的）：

```yaml
tunnel: mytunnel
credentials-file: .cloudflared/mytunnel.json

ingress:
  - hostname: im.clprince.top
    service: http://127.0.0.1:8080
  - service: http_status:404
```

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
cd D:\IHope\docs
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

---

## 五、常用命令

```powershell
# 前台运行（调试）
cd D:\IHope\docs
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

- `docs/.cloudflared/*.json` 等同密钥，**不要提交 Git**
- `config.yml` 含 tunnel 名与域名，已加入 `.gitignore`，每人本地维护
- 内测可用 HTTP；正式 Release APK 建议 VPS + HTTPS

更多 VPS 部署见 [无备案国内部署指南.md](./无备案国内部署指南.md)；Cloudflare 橙云/VPS 方案见 [Cloudflare部署指南.md](./Cloudflare部署指南.md)。
