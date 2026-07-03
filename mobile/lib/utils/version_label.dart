/// 版本字符串：`yyyy-MM-dd {semver} version`
class VersionLabel {
  VersionLabel({required this.date, required this.semver});

  final DateTime date;
  final String semver;

  static final _pattern = RegExp(
    r'^(\d{4}-\d{2}-\d{2})\s+(\S+)\s+version\s*$',
    caseSensitive: false,
  );

  static String format(String isoDate, String semver) =>
      '$isoDate $semver version';

  static VersionLabel? parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final m = _pattern.firstMatch(raw.trim());
    if (m == null) return null;
    final date = DateTime.tryParse(m.group(1)!);
    if (date == null) return null;
    final semver = m.group(2)!;
    if (semver.isEmpty) return null;
    return VersionLabel(date: date, semver: semver);
  }

  String get display => format(
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
        semver,
      );

  /// 负值 = 本版本更旧；0 = 相同；正值 = 本版本更新。
  int compareTo(VersionLabel other) {
    final byDate = _dateOnly(date).compareTo(_dateOnly(other.date));
    if (byDate != 0) return byDate;
    return _compareSemver(semver, other.semver);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _compareSemver(String a, String b) {
    if (a == b) return 0;
    final pa = _semverParts(a);
    final pb = _semverParts(b);
    for (var i = 0; i < 3; i++) {
      final da = i < pa.length ? pa[i] : 0;
      final db = i < pb.length ? pb[i] : 0;
      if (da != db) return da.compareTo(db);
    }
    return a.compareTo(b);
  }

  static List<int> _semverParts(String s) {
    final main = s.split('-').first.split('+').first;
    return main.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  }
}

enum VersionCheckStatus {
  upToDate,
  serverNewer,
  appNewer,
  parseError,
  networkError,
}

class VersionCheckResult {
  VersionCheckResult({
    required this.status,
    required this.appLabel,
    this.serverLabel,
    this.message,
  });

  final VersionCheckStatus status;
  final String appLabel;
  final String? serverLabel;
  final String? message;

  bool get needsAttention => status == VersionCheckStatus.serverNewer;
}

VersionCheckResult compareVersionLabels({
  required String appLabel,
  required String? serverLabelRaw,
}) {
  final app = VersionLabel.parse(appLabel);
  final server = VersionLabel.parse(serverLabelRaw);
  if (app == null) {
    return VersionCheckResult(
      status: VersionCheckStatus.parseError,
      appLabel: appLabel,
      serverLabel: serverLabelRaw,
      message: '本机版本格式无效',
    );
  }
  if (server == null) {
    return VersionCheckResult(
      status: VersionCheckStatus.parseError,
      appLabel: appLabel,
      serverLabel: serverLabelRaw,
      message: serverLabelRaw == null || serverLabelRaw.isEmpty
          ? '服务端未返回版本'
          : '服务端版本格式无效（应为 yyyy-MM-dd x.y.z version）',
    );
  }
  final cmp = app.compareTo(server);
  if (cmp == 0) {
    return VersionCheckResult(
      status: VersionCheckStatus.upToDate,
      appLabel: app.display,
      serverLabel: server.display,
      message: '当前已是最新版本',
    );
  }
  if (cmp < 0) {
    return VersionCheckResult(
      status: VersionCheckStatus.serverNewer,
      appLabel: app.display,
      serverLabel: server.display,
      message: '服务端版本较新，请更新 App',
    );
  }
  return VersionCheckResult(
    status: VersionCheckStatus.appNewer,
    appLabel: app.display,
    serverLabel: server.display,
    message: '本机版本高于服务端（开发构建常见）',
  );
}
