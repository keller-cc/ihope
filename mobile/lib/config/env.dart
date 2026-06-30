/// API / WebSocket 基地址（开发环境）。
///
/// - Android 模拟器访问本机：`10.0.2.2`
/// - Windows / iOS 模拟器 / 真机：改为电脑局域网 IP
class Env {
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static String get wsBase {
    final uri = Uri.parse(apiBase);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.host}:${uri.port}';
  }
}
