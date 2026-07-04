# Flutter 移动端

E2EE 单聊 / 群聊、媒体消息、WebSocket 实时推送。

环境搭建与日常命令见 **[docs/Windows开发环境.md](../docs/Windows开发环境.md)**。

依赖选型原则：通用能力优先用成熟库（dio、intl、uuid 等），业务与 E2EE 编排自研。见 [开发指南](../docs/开发指南.md) 与 `.cursor/rules/prefer-libraries.mdc`。

## 构建（Android）

与 **Flutter 3.44** 模板对齐：**Gradle 9.1**、**AGP 9.0.1**、**Kotlin 2.3.20**。极光已暂移除，可正常用 Gradle 9。

```powershell
cd D:\IHope\mobile
flutter clean
flutter pub get
flutter run -d <设备ID> --flavor domestic
# 或 global：flutter run --flavor global --dart-define-from-file=config/global.json
```

若出现 AGP 9 / newDsl 提示，可先加：`--android-skip-build-dependency-validation`（或按 Flutter 文档开启 `android.newDsl`）。

---

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

## 运行（Android）

**必须先指定 flavor**（`domestic` 国内 / `global` 海外）。JSON 配置**可选**（仅影响离线推送通道）。

```powershell
cd D:\IHope\mobile
flutter pub get

# 日常开发（模拟器，默认连 http://10.0.2.2:8080）
flutter run --flavor domestic -d emulator-5556

# 可选：启用极光/FCM 推送通道
flutter run --flavor domestic --dart-define-from-file=config/domestic.json
```

后端需先启动（见上文或 `docs/Windows开发环境.md`）。构建失败若提示 `jcenter` / Gradle 9，请确认 `android/gradle/wrapper/gradle-wrapper.properties` 为 **Gradle 8.x**（非 9.x）。

## 后台系统通知（国内 / 海外）

类似 QQ 的分层：

1. **前台聊天**：WebSocket 实时；不在当前会话时，App 顶部 **应用内横幅**（回到首页可见，不经系统通知栏）  
2. **后台进程存活**：前台服务保 WebSocket + **系统栏本地通知**（无需第三方）  
3. **App 被系统杀掉**：**FCM**（海外 `global`）；国内离线兜底 **暂不含极光**（见下）

用户在 **个人资料 → 通知** 开启并授权后，**零第三方配置** 即可测第 2 层。登录后 WebSocket 监听同时驱动 **应用内顶部横幅**（前台）与后台系统通知。

**真机建议**：除开启通知外，将 IHope 加入系统 **电池优化白名单 / 允许后台运行**，否则进程易被杀死，只能依赖 FCM/极光离线推送。

```powershell
# 国内 Android（包名 .cn；离线极光暂不可用）
flutter run --flavor domestic

# 海外 Android（离线兜底：FCM，需 google-services.json）
flutter run --flavor global --dart-define-from-file=config/global.json
```

### 极光推送（暂移除）

`jpush_flutter` 3.4.6 仍含 `jcenter()`，与 **Gradle 8.14+** 不兼容，已从依赖移除。国内内测用 **WebSocket + 本地通知**；待官方修复后见 [docs/推送配置指南.md](../docs/推送配置指南.md)。

后端不配 `FCM_SERVER_KEY` 时：在线设备仍可通过 WebSocket + 本地通知收横幅。

## 生产 release APK

1. 复制配置并填写生产 API 地址：

```powershell
cd D:\IHope\mobile
copy config\prod.json.example config\prod.json
# 编辑 prod.json：API_BASE 设为 https://你的域名
```

2. 打 release 包（国内 / 海外 flavor）：

```powershell
.\scripts\build-release.ps1                    # domestic + global
.\scripts\build-release.ps1 -Flavor domestic   # 仅国内
.\scripts\build-release.ps1 -ApiBase "https://im.example.com"  # 覆盖 prod.json
```

输出：`build\app\outputs\flutter-apk\app-<flavor>-release.apk`。

**Android 网络安全：** release 且 `API_BASE` 为 `https://` 时禁止明文 HTTP；debug 始终允许；release 若 `--dart-define=API_BASE=http://...` 则允许 HTTP（局域网联调包）。

上传到服务器：见 [deploy/README.md](../deploy/README.md)「发布 APK」。

### GitHub Actions 发布

无需本地 Android SDK，在 GitHub 上构建并发布到 **Releases**：

1. 仓库 **Settings → Secrets → Actions** 添加 **`API_BASE`**（与 `prod.json` 相同，如 `https://im.example.com`）
2. **Actions → Release APK → Run workflow**，分支选 **main**，Tag 填 `v2026-07-04-0.1.0`（或已有 tag）
3. 成功后到 [GitHub Releases](https://github.com/keller-cc/ihope/releases) 下载 `app-domestic-release.apk`

推送 `v*` tag 也会自动触发；工作流（`softprops/action-gh-release`）始终从 **main** 最新代码构建 domestic APK（避免旧 tag 缺少 CI 修复）。

无 `gh` CLI 时，可用根目录 `scripts/publish-github-release.ps1` 手动上传本地 APK（需 `GITHUB_TOKEN`）。

### Gradle 国内镜像（仅本地）

在 `mobile/android/local.properties`（勿提交 git）增加：

```properties
useCnMavenMirror=true
```

国内 Gradle 下载慢或 Aliyun 502 时可启用。**GitHub Actions / CI** 固定 `ORG_GRADLE_PROJECT_useCnMavenMirror=false`，不走国内镜像。

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
