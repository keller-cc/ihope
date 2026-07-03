# Flutter 移动端

E2EE 单聊 / 群聊、媒体消息、WebSocket 实时推送。

环境搭建与日常命令见 **[docs/Windows开发环境.md](../docs/Windows开发环境.md)**。

依赖选型原则：通用能力优先用成熟库（dio、intl、uuid 等），业务与 E2EE 编排自研。见 [开发指南](../docs/开发指南.md) 与 `.cursor/rules/prefer-libraries.mdc`。

## 初始化

```powershell
cd D:\IHope\mobile
flutter pub get
```

若缺少 `android/` 等平台目录：`flutter create --org com.clprince --project-name ihope .`（不覆盖已有 `lib/`）。

## API / 服务器地址

编译默认（`lib/config/env.dart` 或 `--dart-define=API_BASE=...`）：

| 场景 | 默认地址 |
|------|----------|
| Android 模拟器 | `http://10.0.2.2:8080` |
| Windows / iOS 模拟器 | `http://localhost:8080` |
| 真机（同 WiFi） | `http://<电脑局域网IP>:8080` |

**App 内可改**：登录页 →「服务器：…」/ 个人资料 → **服务器**（保存后需重新登录）。

## 应用图标

源图 `assets/icon/app_icon.png`（1024×1024 满幅方形，摩西 · 燃烧荆棘）。系统会自动圆角裁剪；改图后执行 `dart run flutter_launcher_icons`。

## 后台系统通知（国内 / 海外）

类似 QQ 的分层：

1. **前台聊天**：WebSocket，当前会话不弹横幅  
2. **后台进程存活**：前台服务保 WebSocket + **本地系统通知**（无需极光/FCM）  
3. **App 被系统杀掉**：极光（国内）/ FCM（海外）离线兜底  

用户在 **个人资料 → 通知** 开启并授权后，**零第三方配置** 即可测第 2 层。第 3 层见 **[docs/推送配置指南.md](../docs/推送配置指南.md)**。

```powershell
# 国内 Android（离线兜底：极光）
flutter run --flavor domestic --dart-define-from-file=config/domestic.json

# 海外 Android（离线兜底：FCM，需 google-services.json）
flutter run --flavor global --dart-define-from-file=config/global.json
```

后端不配 `JPUSH_*` / `FCM_SERVER_KEY` 时：在线设备仍可通过 WebSocket + 本地通知收横幅；仅 **被杀进程** 后无离线兜底。

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
