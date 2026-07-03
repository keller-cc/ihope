import '../config/app_config.dart';
import '../config/app_version.dart';
import '../services/api_client.dart';
import '../utils/version_label.dart';

class VersionCheckService {
  VersionCheckService(this._api);

  final ApiClient _api;

  Future<VersionCheckResult> check({bool refreshRemote = true}) async {
    final appLabel = await AppVersionInfo.displayLabel();
    if (refreshRemote) {
      await AppConfig.refresh(_api);
    }
    try {
      return compareVersionLabels(
        appLabel: appLabel,
        serverLabelRaw: AppConfig.serverVersion,
      );
    } catch (e) {
      return VersionCheckResult(
        status: VersionCheckStatus.networkError,
        appLabel: appLabel,
        serverLabel: AppConfig.serverVersion.isEmpty
            ? null
            : AppConfig.serverVersion,
        message: '无法连接服务器：$e',
      );
    }
  }
}
