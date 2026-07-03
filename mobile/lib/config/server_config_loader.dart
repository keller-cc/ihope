import '../config/env.dart';
import '../config/server_config.dart';
import 'auth_storage.dart';

/// 启动时从安全存储恢复用户自定义服务器地址。
Future<void> bootstrapServerConfig(AuthStorage storage) async {
  final saved = await storage.readServerBaseUrl();
  if (saved != null && saved.isNotEmpty) {
    ServerConfig.setApiBase(saved);
  } else {
    ServerConfig.setApiBase(Env.defaultApiBase);
  }
}

/// 保存并应用新的 API 基地址。
Future<void> applyServerBaseUrl(AuthStorage storage, String url) async {
  final normalized = ServerConfig.normalizeApiBase(url);
  await storage.writeServerBaseUrl(normalized);
  ServerConfig.setApiBase(normalized);
}

Future<void> resetServerBaseUrl(AuthStorage storage) async {
  await storage.clearServerBaseUrl();
  ServerConfig.setApiBase(Env.defaultApiBase);
}
