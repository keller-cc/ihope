# IHope 管理后台（Web）

开发者运维页面：用户列表、搜索、用户详情、设备踢下线、禁用/启用账号。**不能查看消息明文**（E2EE）。  
**不依赖 App 用户账号**，与聊天用户体系完全分离。

## 访问

后端启动后打开：

```
http://localhost:8080/admin/
```

## 开发者密钥

在 `deploy/.env` 配置：

```env
ADMIN_SECRET=your-long-random-dev-secret
```

改完后 **重启后端**。管理页输入同一密钥即可。

## 功能

| 区域 | 说明 |
|------|------|
| 服务状态 | API / 数据库连通、运行时间、推送 token 按平台统计 |
| 用户列表 | 按 **用户名排序**，分页（每页 20）；顶部总数为全库 `COUNT(*)` |
| 搜索 | 用户名或邮箱模糊匹配（如 `alice`、`bob`） |
| 用户详情 | 注册信息、设备列表、单设备踢下线 |
| 禁用/启用 | 整号封禁并清除所有 refresh token |

### 为何总数对但列表里看不到某些人？

旧版列表按 **注册时间倒序** 且一次只拉前 100 条，较早注册的 alice/bob 可能被挤到后面；**统计总数仍是全库计数**。现已改为按用户名排序 + 分页 + 搜索。

## API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin/stats` | 用户/禁用/推送/服务状态 |
| GET | `/api/admin/users?q=&sort=&order=&limit=&offset=` | 用户列表；表头三态：**升序 → 降序 → 取消**（取消时不传 `sort`，默认用户名升序） |
| GET | `/api/admin/users/{id}` | 用户详情 + 设备 |
| POST | `/api/admin/users/{id}/disable` | 禁用 |
| POST | `/api/admin/users/{id}/enable` | 启用 |
| POST | `/api/admin/users/{id}/devices/{deviceId}/kick` | 踢单设备 |

以上接口均需 `Authorization: Bearer <ADMIN_SECRET>`。

## 设备连接状态

| 显示 | 含义 |
|------|------|
| 在线 | WebSocket 已连接 |
| 已登录 | 库中有 refresh token，且在 `REFRESH_TOKEN_TTL_DAYS` 内有过活跃 |
| 闲置 | 库中仍有 token，但超过 TTL 未 refresh（三天前的常见情况） |
| — | 无 refresh token |

`deploy/.env` 可配置 `REFRESH_TOKEN_TTL_DAYS=30`（0 表示永不过期，仅建议开发环境）。App 退出会调用 `POST /api/auth/logout` 清除当前设备 token。
