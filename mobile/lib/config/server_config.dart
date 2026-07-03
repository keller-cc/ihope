import 'env.dart';

/// 运行时 API 基地址（用户可在 App 内覆盖编译默认值）。
class ServerConfig {
  ServerConfig._();

  static String _apiBase = Env.defaultApiBase;

  static String get apiBase => _apiBase;

  static String get wsBase {
    final uri = Uri.parse(_apiBase);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://${uri.host}$port';
  }

  static void setApiBase(String url) {
    _apiBase = normalizeApiBase(url);
  }

  /// 去掉末尾斜杠，补全 scheme。
  static String normalizeApiBase(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return Env.defaultApiBase;
    if (!s.contains('://')) {
      s = 'http://$s';
    }
    final uri = Uri.parse(s);
    if (uri.host.isEmpty) return Env.defaultApiBase;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }
}
