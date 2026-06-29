# Flutter 移动端

在项目根目录执行（需已安装 Flutter SDK）：

```powershell
flutter create --org com.ihope --project-name ihope .
flutter pub add dio web_socket_channel flutter_secure_storage
```

然后将 `lib/config/env.dart` 中的 API 地址指向本地后端：

```dart
const apiBase = 'http://10.0.2.2:8080';  // Android 模拟器访问本机
// 真机调试改为电脑局域网 IP，如 http://192.168.1.10:8080
```

详细步骤见 [docs/Windows开发环境.md](../docs/Windows开发环境.md)。
