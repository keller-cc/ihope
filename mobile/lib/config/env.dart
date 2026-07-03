/// API / WebSocket 基地址（开发环境）。
///
/// - Android 模拟器访问本机：`10.0.2.2`
/// - Windows / iOS 模拟器 / 真机：改为电脑局域网 IP
///
/// 运行时可在 App「服务器设置」中覆盖；见 [ServerConfig]。
class Env {
  static const defaultApiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8080',
  );

  @Deprecated('Use ServerConfig.apiBase')
  static String get apiBase => defaultApiBase;

  @Deprecated('Use ServerConfig.wsBase')
  static String get wsBase {
    final uri = Uri.parse(defaultApiBase);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.host}:${uri.port}';
  }
}
