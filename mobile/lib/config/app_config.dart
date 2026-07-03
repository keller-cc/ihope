import '../services/api_client.dart';

/// 从 `GET /api/health` 同步客户端可见配置（env 驱动，改 env 后重启后端生效）。
class AppConfig {
  AppConfig._();

  static const _defaultMaxFileBytes = 300 * 1024 * 1024;
  static const _defaultCloudDriveUrl = 'https://1t1.org';

  static int maxFileBytes = _defaultMaxFileBytes;
  static String cloudDriveUrl = _defaultCloudDriveUrl;
  static String serverVersion = '';
  static String appDownloadUrl = '';

  static int get fileRecommendBytes => maxFileBytes;

  static Future<void> refresh(ApiClient api) async {
    try {
      final data = await api.getJson('/api/health');
      serverVersion = data['version'] as String? ?? '';
      final client = data['client'];
      if (client is! Map<String, dynamic>) return;
      final max = client['max_encrypted_file_bytes'];
      if (max is int && max > 0) {
        maxFileBytes = max;
      } else if (max is num && max > 0) {
        maxFileBytes = max.toInt();
      } else if (max == 0) {
        maxFileBytes = 1 << 30; // 服务端 0 = 不限制
      }
      final url = client['cloud_drive_url'];
      if (url is String && url.isNotEmpty) {
        cloudDriveUrl = url;
      }
      final dl = client['app_download_url'];
      if (dl is String) {
        appDownloadUrl = dl;
      }
    } catch (_) {
      // 保留上次或默认值
    }
  }

  static void resetToDefaults() {
    maxFileBytes = _defaultMaxFileBytes;
    cloudDriveUrl = _defaultCloudDriveUrl;
    serverVersion = '';
    appDownloadUrl = '';
  }
}
