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
      final now = DateTime(2026, 6, 29, 15, 30);
      final today = DateTime(2026, 6, 29, 9, 5);
      final yesterday = DateTime(2026, 6, 28, 9, 5);
      final lastYear = DateTime(2025, 1, 2, 9, 5);

      expect(
        MessageTimeFormat.formatDivider(today),
        '09:05',
      );
      expect(
        MessageTimeFormat.formatDivider(yesterday),
        '昨天 09:05',
      );
      expect(
        MessageTimeFormat.formatDivider(lastYear),
        '2025年1月2日 09:05',
      );

      // Keep `now` referenced so tests stay anchored to the same calendar day.
      expect(now.day, 29);
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
