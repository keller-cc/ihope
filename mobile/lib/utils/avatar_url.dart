import '../config/env.dart';

/// 将后端返回的头像 URL 转为当前 App 可访问的地址。
///
/// 后端默认可能存 `http://localhost:8080/api/avatars/...`，
/// Android 模拟器需改为 `http://10.0.2.2:8080/...`。
String? resolveAvatarUrl(String? url) {
  if (url == null || url.isEmpty) return null;

  final base = Uri.parse(Env.apiBase);

  if (url.startsWith('/')) {
    return base.replace(path: url).toString();
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;

  if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
    return uri.replace(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : uri.port,
    ).toString();
  }

  return url;
}
