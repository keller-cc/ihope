# Web 前端

Vite + React 19 SPA。路径别名：`@/` → `src/`。

## 目录

```
src/
  api/           # HTTP 客户端（types / client / admin）
  assets/        # 静态资源
  components/
    call/        # 音视频通话 UI
    chat/        # 会话面板、主题、转发、看图
    contacts/    # 会话列表、联系人、好友/群资料
    history/     # 查找聊天记录
    Avatar.tsx   # 跨域共用组件
    PlusMenu.tsx
    UserDrawer.tsx
  hooks/         # 通用 hooks
  lib/           # 领域逻辑（call、chatBg、chatFormat…）
  pages/         # 路由页
  styles/        # tokens / layout / 按域拆分的 CSS
```

## 脚本

- `pnpm dev` — 开发（代理到 appserver `:8090`）
- `pnpm build` — 类型检查 + 生产构建（含 PWA）
- `pnpm lint` — oxlint
