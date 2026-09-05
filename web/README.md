# web

独立 Web IM 前端（Vite + React + TypeScript + TDesign）。

与旧 Flutter `mobile/` 无关；对接 `appserver/`（默认 `:8090`）。

## 开发

```bash
pnpm install
pnpm run dev
```

Vite 已将 `/api`、`/ws`、`/health` 代理到 `http://127.0.0.1:8090`。

先启动 appserver，再打开 http://localhost:5173 。

### 双账号同浏览器测试

同一 origin 下默认共用 `localStorage`，两个标签会串登录态。可开隔离槽：

- http://localhost:5173/?slot=a
- http://localhost:5173/?slot=b

也可用无痕窗口 / 另一个浏览器配置文件。

## 生产构建

```bash
pnpm install
pnpm run build
```

将 `dist/` 交给 Nginx 托管；与 `appserver` 同源部署时无需 Vite 代理。本地联调见 [../appserver/README.md](../appserver/README.md)。
