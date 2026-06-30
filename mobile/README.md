# Flutter 移动端（阶段 2）

明文单聊：登录 / 注册、会话列表、聊天页、WebSocket 实时收消息。

## 首次初始化

在 `mobile/` 目录执行（需已安装 Flutter SDK）：

```powershell
cd D:\施玮书房\IHope\mobile

# 若尚无 android/ ios/ 等平台目录，先生成工程骨架
flutter create --org com.ihope --project-name ihope .

flutter pub get
```

`lib/` 下源码已在仓库中；`flutter create` 只会补全平台目录，不会覆盖已有 `lib/main.dart`。

## 国内镜像（Flutter / Pub / 引擎）

Gradle 日志里若出现从 `storage.googleapis.com/download.flutter.io` 下载且很慢，需要设 **Flutter 存储镜像**（`flutter pub get` 与 **Android 编译拉引擎** 都会用到）。

### 方式 A：永久设置（推荐）

```powershell
cd D:\施玮书房\IHope\mobile
PowerShell -ExecutionPolicy Bypass -File .\setup-mirror-env.ps1
```

然后 **关掉终端再开**，验证：

```powershell
echo $env:FLUTTER_STORAGE_BASE_URL   # 应为 https://storage.flutter-io.cn
echo $env:PUB_HOSTED_URL             # 应为 https://pub.flutter-io.cn
```

### 方式 B：仅当前终端

```powershell
cd D:\施玮书房\IHope\mobile
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
flutter run -d android
```

或直接：

```powershell
.\run-android.ps1
# 指定设备： .\run-android.ps1 -Device emulator-5554
```

设置成功后，`flutter run` 开头应出现类似：

```text
Flutter assets will be downloaded from https://storage.flutter-io.cn
```

引擎 jar 会走镜像，而不是 `storage.googleapis.com`。

## 配置 API 地址

编辑 `lib/config/env.dart`，或运行时指定：

| 场景 | `API_BASE` |
|------|------------|
| Android 模拟器（默认） | `http://10.0.2.2:8080` |
| Windows 桌面 / iOS 模拟器 | `http://localhost:8080` |
| 真机（同一 WiFi） | `http://<电脑局域网IP>:8080` |

```powershell
flutter run --dart-define=API_BASE=http://192.168.1.10:8080
```

## 运行

1. 启动数据库与后端（见 [docs/Windows开发环境.md](../docs/Windows开发环境.md)）
2. `flutter run`（选 Android 模拟器或已连接设备）

## 功能（阶段 2）

- 注册 / 登录（token 存 Secure Storage）
- 会话列表（`GET /api/conversations`）
- 发起单聊（用户列表 → `POST /api/conversations`）
- 聊天页：拉历史 + REST 发消息 + WebSocket 收 `message` 推送
- 阶段 2 **明文** 存在 `ciphertext` 字段（阶段 3 再上 E2EE）

## 目录

```
mobile/lib/
├── config/env.dart
├── models/
├── services/     # api, auth, conversation, ws
├── screens/      # login, register, conversations, chat
├── app.dart
└── main.dart
```

详细步骤见 [docs/Windows开发环境.md](../docs/Windows开发环境.md)、[docs/开发指南.md](../docs/开发指南.md) §5.2。

## Gradle 下载超时（国内网络）

`flutter run` 报 `GradleWrapperMain` / `Connection timed out` 时：

1. 项目已配置 **腾讯云 Gradle** + **阿里云 Maven** 镜像（见 `android/`）
2. 清理失败缓存后重试：

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.gradle\wrapper\dists\gradle-9.1.0-all" -ErrorAction SilentlyContinue
cd D:\施玮书房\IHope\mobile
flutter clean
flutter pub get
flutter run -d android
```

3. 若仍失败：开 VPN，或在 Android Studio **Settings → HTTP Proxy** 配好代理后重试。

## 路径含中文（施玮书房等）

Android 构建报错 `non-ASCII characters` 时，已在 `android/gradle.properties` 加 `android.overridePathCheck=true`。

更稳妥做法：把整个仓库 clone 到纯英文路径，例如 `D:\Dev\IHope`，再 `flutter run`。
