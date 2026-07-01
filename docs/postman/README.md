# docs/postman — 已停用

**唯一来源：`postman/` 目录（Native Git + yaml）。**

本目录下的 JSON **不再维护**，也 **不要** 写进 `.postman/resources.yaml`（否则 Workspace 会同时出现 **IHope API** 和 **IHope.postman_collection.json** 两个集合）。

## Workspace 里多了 JSON 集合？

1. 确认 `.postman/resources.yaml` 的 `localResources.collections` **只有** `postman/collections/IHope API`
2. Postman **Pull** 同步
3. 在 Collections 里 **删除** `IHope.postman_collection.json`（右键 Delete）
4. 只用 **IHope API**（来自 yaml）

## 完全无法使用 Native Git 时

可 **一次性** Import 本目录 JSON（离线备用），但不要与 **IHope API** yaml 集合同时启用。

需要新 API 时请以 `postman/collections/IHope API/` 为准；JSON 不会自动跟上。

## 若仍要导出 JSON（可选）

在已安装 Postman CLI 的机器上，从 v3 yaml 迁移导出（版本以官方文档为准）：

```text
cd <仓库根目录>
postman collection migrate postman/collections/IHope API --output docs/postman/export
```

日常开发 **不要** 依赖此流程。
