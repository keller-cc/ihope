# IHope 管理后台（Web）

简易运维页面：用户列表、禁用/启用账号。**不能查看消息明文**（E2EE）。

## 访问

后端启动后打开：

```
http://localhost:8080/admin/
```

也可单独指定静态目录：

```env
ADMIN_WEB_DIR=D:\IHope\admin
```

## 管理员账号

在 `deploy/.env` 配置管理员邮箱（逗号分隔）：

```env
ADMIN_EMAILS=ops@example.com,alice@example.com
```

使用该邮箱 **正常注册/登录 App 或管理页** 后，系统会自动赋予 `is_admin`。仅管理员可调用 `/api/admin/*`。

## API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin/stats` | 用户总数、禁用数 |
| GET | `/api/admin/users` | 用户列表 |
| POST | `/api/admin/users/{id}/disable` | 禁用并踢下线 |
| POST | `/api/admin/users/{id}/enable` | 解除禁用 |

禁用账号会递增 `token_version` 并清除 refresh token，已登录设备立即失效。
