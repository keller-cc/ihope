import 'package:package_info_plus/package_info_plus.dart';

import '../utils/version_label.dart';

/// 本机 App 版本（与后端 [SERVER_VERSION] 同格式）。
class AppVersionInfo {
  AppVersionInfo._();

  /// 发版日期；构建时可 `--dart-define=APP_RELEASE_DATE=2026-07-03` 覆盖。
  static const releaseDate = String.fromEnvironment(
    'APP_RELEASE_DATE',
    defaultValue: '2026-07-03',
  );

  static PackageInfo? _info;

  static Future<PackageInfo> _load() async {
    return _info ??= await PackageInfo.fromPlatform();
  }

  static Future<String> displayLabel() async {
    final info = await _load();
    return VersionLabel.format(releaseDate, info.version);
  }

  static Future<String> semver() async {
    return (await _load()).version;
  }
}
