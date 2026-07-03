import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/utils/version_label.dart';

void main() {
  test('format and parse', () {
    const raw = '2026-07-03 0.1.0 version';
    expect(VersionLabel.format('2026-07-03', '0.1.0'), raw);
    final v = VersionLabel.parse(raw);
    expect(v, isNotNull);
    expect(v!.display, raw);
  });

  test('compare by date then semver', () {
    final older = VersionLabel.parse('2026-07-01 0.2.0 version')!;
    final newerDate = VersionLabel.parse('2026-07-03 0.1.0 version')!;
    expect(older.compareTo(newerDate), lessThan(0));

    final sameDateOld = VersionLabel.parse('2026-07-03 0.1.0 version')!;
    final sameDateNew = VersionLabel.parse('2026-07-03 0.2.0 version')!;
    expect(sameDateOld.compareTo(sameDateNew), lessThan(0));
  });

  test('compareVersionLabels server newer', () {
    final r = compareVersionLabels(
      appLabel: '2026-07-03 0.1.0 version',
      serverLabelRaw: '2026-07-04 0.1.0 version',
    );
    expect(r.status, VersionCheckStatus.serverNewer);
  });

  test('compareVersionLabels up to date', () {
    final r = compareVersionLabels(
      appLabel: '2026-07-03 0.1.0 version',
      serverLabelRaw: '2026-07-03 0.1.0 version',
    );
    expect(r.status, VersionCheckStatus.upToDate);
  });
}
