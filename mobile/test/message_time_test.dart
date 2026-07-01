import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/utils/message_time.dart';

void main() {
  group('MessageTimeFormat', () {
    test('shows divider when gap is 5 minutes or more', () {
      final prev = DateTime(2026, 6, 29, 10, 0);
      final current = DateTime(2026, 6, 29, 10, 4, 59);
      expect(MessageTimeFormat.shouldShowDivider(prev, current), isFalse);

      final later = DateTime(2026, 6, 29, 10, 5);
      expect(MessageTimeFormat.shouldShowDivider(prev, later), isTrue);
      expect(MessageTimeFormat.shouldShowDivider(null, later), isTrue);
    });

    test('formats divider for today, yesterday, and older dates', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9, 5);
      final yesterday = today.subtract(const Duration(days: 1));
      final lastYear = DateTime(now.year - 1, 1, 2, 9, 5);

      expect(MessageTimeFormat.formatDivider(today), '09:05');
      expect(MessageTimeFormat.formatDivider(yesterday), '昨天 09:05');
      expect(
        MessageTimeFormat.formatDivider(lastYear),
        '${lastYear.year}年1月2日 09:05',
      );
    });

    test('formats bubble time', () {
      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        14,
        8,
      );
      expect(MessageTimeFormat.formatBubble(today), '14:08');
    });
  });
}
