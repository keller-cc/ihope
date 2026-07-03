# Flutter 移动端

E2EE 单聊 / 群聊、媒体消息、WebSocket 实时推送。

环境搭建与日常命令见 **[docs/Windows开发环境.md](../docs/Windows开发环境.md)**。

依赖选型原则：通用能力优先用成熟库（dio、intl、uuid 等），业务与 E2EE 编排自研。见 [开发指南](../docs/开发指南.md) 与 `.cursor/rules/prefer-libraries.mdc`。

## 初始化

```powershell
cd D:\IHope\mobile
flutter pub get
```

若缺少 `android/` 等平台目录：`flutter create --org com.ihope --project-name ihope .`（不覆盖已有 `lib/`）。

## API 地址

编辑 `lib/config/env.dart`，或运行时：

```powershell
flutter run --dart-define=API_BASE=http://192.168.1.10:8080
```

| 场景 | 默认 `API_BASE` |
|------|-----------------|
| Android 模拟器 | `http://10.0.2.2:8080` |
| Windows / iOS 模拟器 | `http://localhost:8080` |
| 真机（同 WiFi） | `http://<电脑局域网IP>:8080` |

## 双模拟器联调

1. Android Studio → Device Manager 启动两个 AVD  
2. `flutter devices` 查看 ID（如 `emulator-5554`、`emulator-5556`）  
3. 两个终端分别执行：`flutter run -d emulator-5554` / `flutter run -d emulator-5556`  
4. 注册 `alice@example.com`、`bob@example.com`（密码 `password123`）

## 目录

```
mobile/lib/
├── config/       # env.dart
├── models/
├── services/     # api, auth, ws
├── screens/
└── widgets/
```

构建异常（Gradle 超时、缓存损坏）见 [Windows 开发环境 §5](../docs/Windows开发环境.md#5-构建排错)。
