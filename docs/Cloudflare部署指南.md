# Cloudflare 部署指南

IHope 可通过 Cloudflare 获得：**免费 HTTPS**、**隐藏源站 IP**、**基础 DDoS 防护**、**全球 CDN**。本文说明两种常用方式及 IHope 特有注意事项。

---

## 方式对比

| 方式 | 适用 | 源站要开 80/443 | 隐藏 IP |
|------|------|-----------------|--------|
| **A. 橙云代理**（推荐入门） | 已有 VPS + 域名在 CF | 是（建议仅允许 CF IP 访问） | 较好 |
| **B. Cloudflare Tunnel** | 不想暴露任何端口 / 家宽无公网 IP | **否** | 最好 |

两种方式都需在 Cloudflare 控制台 **开启 WebSockets**（`Network` → `WebSockets` = ON），否则 `/ws` 聊天会断。

---

## 方式 A：橙云代理 + VPS Docker

### 架构

```
App / 浏览器
    │  HTTPS (im.example.com)
    ▼
Cloudflare（橙云）
    │  HTTP 或 HTTPS → 源站
    ▼
VPS :80  nginx (deploy/nginx-cloudflare.conf.example)
    ▼
backend :8080
```

### 1. Cloudflare DNS

1. 域名 NS 指向 Cloudflare
2. 添加 **A 记录**：`im` → VPS 公网 IP，**代理状态：已代理（橙云）**
3. （可选）`upload.im` → 同一 IP，**仅 DNS（灰云）** — 见下文「大文件上传」

### 2. SSL/TLS 模式

| 模式 | 源站 nginx | 说明 |
|------|------------|------|
| **Flexible** | 仅 HTTP :80 | 最快上手；CF→源站无加密，不推荐长期 |
| **Full (strict)**（推荐） | HTTPS + CF Origin Certificate | 控制台 `SSL/TLS` → `Origin Server` → 创建证书，挂到 nginx 443 |

`APP_PUBLIC_URL`、App `prod.json` 的 `API_BASE` 均填：**`https://im.example.com`**（用户侧始终走 CF HTTPS）。

### 3. VPS 部署

```bash
cd /opt/ihope/deploy
cp ../.env.example .env
# APP_PUBLIC_URL=https://im.example.com
docker compose up -d --build
```

将 Nginx 配置换成 Cloudflare 版：

```bash
cp nginx-cloudflare.conf.example nginx.conf
# 改 server_name 为你的域名

# 生成 Cloudflare IP 白名单（real_ip 用）
curl -s https://www.cloudflare.com/ips-v4 \
  | sed 's/^/set_real_ip_from /;s/$/;/' > cloudflare-ips-v4.conf

# compose 中 nginx volumes 增加（示例）：
#   - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
#   - ./cloudflare-ips-v4.conf:/etc/nginx/cloudflare-ips-v4.conf:ro
docker compose up -d --force-recreate nginx
```

**防火墙（强烈建议）**：VPS 上 80/443 **仅允许 Cloudflare IP 段**访问，避免绕过 CF 直连源站。IP 列表：<https://www.cloudflare.com/ips-v4> 与 `ips-v6`。

### 4. App 与后台

```powershell
# mobile/config/prod.json
{ "API_BASE": "https://im.example.com" }

.\scripts\build-release.ps1
```

管理后台：`https://im.example.com/admin/`

---

## 方式 B：Cloudflare Tunnel（cloudflared）

无需在 VPS 开放 80/443；Tunnel 出站连 Cloudflare。

### 简要步骤

1. Cloudflare Zero Trust → **Networks** → **Tunnels** → 创建 Tunnel
2. 在 VPS 安装 `cloudflared`，按向导登录并运行 connector
3. 添加 **Public Hostname**：`im.example.com` → `http://backend:8080` 或 `http://nginx:80`（若 compose 内网）
4. 同样开启 WebSockets

Tunnel 模式下大文件上传仍受 **CF 边缘 100MB 限制**（见下），需灰云子域或 R2 等方案。

---

## ⚠️ 大文件上传（300MB）

IHope IM 附件上限 **300MB**，但 Cloudflare **橙云代理**对单次上传约 **100MB** 上限（Free/Pro/Business）。

| 方案 | 做法 |
|------|------|
| **灰云上传子域**（推荐） | `upload.im.example.com` 灰云 → 直连 VPS；App 大文件走该域名（需改客户端上传 URL 逻辑，当前未实现） |
| **接受 100MB** | 仅经橙云时实际上限 100MB；更大文件引导 **1t1 网盘**（已有） |
| **Enterprise** | 可提更高上限，成本高 |

当前版本：**经橙云的主域名** 上传 >100MB 会失败；≤100MB 正常。语音/小图/普通文件无影响。

---

## WebSocket（聊天实时）

- 控制台：**Network → WebSockets = ON**
- Nginx 已配置 `/ws` Upgrade 头（见 `nginx-cloudflare.conf.example`）
- App 使用 `wss://im.example.com/ws`（由 `ServerConfig.wsBase` 从 HTTPS 自动推导）

---

## 登录限流与真实 IP

后端 `httpx.ClientIP` 优先读 **`CF-Connecting-IP`**（经 Nginx 转发后），登录限流按真实用户 IP 计数。

**前提**：源站仅 Cloudflare 可访问，或 Nginx 用 `real_ip` 从 CF 段还原 IP，避免伪造头。

---

## 与 certbot 的关系

- **用 Cloudflare 橙云 + Flexible / Full**：用户侧 HTTPS 由 **CF 提供**，源站可不必 certbot
- **Full (strict)**：源站用 **Cloudflare Origin Certificate**（15 年），不必 Let's Encrypt
- 若不用 CF、直连 VPS：仍用 `nginx-ssl.conf.example` + certbot（见 [deploy/README.md](../deploy/README.md)）

---

## 检查清单

- [ ] DNS 橙云 / Tunnel 已指向服务
- [ ] WebSockets 已开启
- [ ] SSL 模式与源站证书一致
- [ ] `APP_PUBLIC_URL` = `https://你的域名`
- [ ] `curl https://im.example.com/api/health` 正常
- [ ] App 登录、发消息、WS 在线
- [ ] 了解 >100MB 文件需网盘或灰云子域

---

## 参考

- [Cloudflare IP ranges](https://www.cloudflare.com/ips/)
- [WebSockets on Cloudflare](https://developers.cloudflare.com/network/websockets/)
- 项目 compose：[deploy/docker-compose.yml](../deploy/docker-compose.yml)
