# Windows 开发环境

仓库路径：**`D:\IHope`**。一人开发、Windows + GitHub。

---

## 1. D 盘目录（推荐）

| 用途 | 路径 | 用户环境变量 |
|------|------|-------------|
| 本仓库 | `D:\IHope` | — |
| Android SDK | `D:\Android\Sdk` | `ANDROID_HOME`、`ANDROID_SDK_ROOT` |
| 模拟器 | `D:\Android\avd` | `ANDROID_AVD_HOME`（须先建目录） |
| Gradle 缓存 | `D:\Gradle` | `GRADLE_USER_HOME` |

```text
flutter config --android-sdk D:\Android\Sdk
```

`mobile/android/local.properties`（本地，不提交）：

```properties
sdk.dir=D\:\\Android\\Sdk
```

改环境变量后重启 IDE / 终端。

### Flutter 国内镜像（可选）

在 **系统 → 环境变量 → 用户变量** 新增：

| 变量 | 值 |
|------|-----|
| `FLUTTER_STORAGE_BASE_URL` | `https://storage.flutter-io.cn` |
| `PUB_HOSTED_URL` | `https://pub.flutter-io.cn` |

Gradle / Maven 镜像已写在 `mobile/android/` 配置中。

---

## 2. 软件

| 软件 | 验证 |
|------|------|
| Git | `git --version` |
| Go 1.22+ | `go version` |
| Docker Desktop | `docker compose version` |
| Flutter | `flutter doctor` |
| Android Studio | AVD Manager |

`flutter doctor --android-licenses` 接受协议。Windows 无法本地编 iOS。

---

## 3. 日常启动

**数据库**（在 `deploy` 目录，首次 `copy ..\.env.example .env`）：

```powershell
cd D:\IHope\deploy
docker compose -f docker-compose.dev.yml up -d
```

**后端**（自动读 `deploy/.env`）：

```powershell
cd D:\IHope\backend
go run ./cmd/server
```

健康检查：`curl http://localhost:8080/api/health`

**移动端**：

```powershell
cd D:\IHope\mobile
flutter pub get
flutter run
```

| 访问后端 | API 基地址 |
|----------|------------|
| Android 模拟器 | `http://10.0.2.2:8080` |
| 本机 | `http://localhost:8080` |
| 真机 | `http://<局域网IP>:8080` |

测试：`cd backend` → `go test ./... -count=1`

---

## 4. Navicat（PostgreSQL）

| 字段 | 值 |
|------|-----|
| 主机 | `127.0.0.1` |
| 端口 | `deploy/.env` 的 `DB_PORT`（默认 5432） |
| 库 / 用户 | `ihope` / `ihope` |
| 密码 | `deploy/.env` 的 `DB_PASSWORD` |

连不上：确认 Docker 已启、端口与 `.env` 一致；改密码后需 `docker compose down` 并删 `deploy/data/postgres` 重建卷。

---

## 5. 构建排错

**Gradle 下载超时** — 项目已配国内镜像；仍失败时删 `%USERPROFILE%\.gradle\wrapper\dists\gradle-9.1.0-all` 后 `flutter clean && flutter pub get`。

**Kotlin 缓存损坏**（`incremental caches` 等）：

```powershell
cd D:\IHope\mobile\android
gradlew.bat --stop
cd ..
flutter clean
flutter pub get
flutter run
```

**找不到 SDK** — 检查 `ANDROID_HOME`、`flutter config --android-sdk` 与 `local.properties` 的 `sdk.dir`。

---

## 6. 换机恢复

```powershell
git clone <仓库URL> D:\IHope
cd D:\IHope\deploy
copy ..\.env.example .env
docker compose -f docker-compose.dev.yml up -d
cd ..\backend
go mod download
go run ./cmd/server
```

按 §1 配置 Android SDK / 环境变量，再 `cd mobile && flutter pub get`。

---

## 7. 其他

- Postman：见 [postman/README.md](../postman/README.md)
- 分阶段路线：见 [开发指南.md](./开发指南.md)
- 切勿提交：`.env`、`deploy/data/`、`mobile/build/`、`local.properties`
