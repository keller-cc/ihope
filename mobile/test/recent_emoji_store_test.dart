import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/services/recent_emoji_store.dart';

void main() {
  group('mergeRecentEmoji', () {
    test('prepends new emoji', () {
      expect(
        mergeRecentEmoji(['😊', '🙏'], '❤️'),
        ['❤️', '😊', '🙏'],
      );
    });

    test('dedupes and moves to front', () {
      expect(
        mergeRecentEmoji(['😊', '🙏', '❤️'], '🙏'),
        ['🙏', '😊', '❤️'],
      );
    });

    test('trims to max count', () {
      final current = List<String>.generate(40, (i) => '$i');
      final next = mergeRecentEmoji(current, 'new', maxCount: 36);
      expect(next.length, 36);
      expect(next.first, 'new');
      expect(next.last, '3');
    });

    test('ignores empty emoji', () {
      expect(mergeRecentEmoji(['😊'], ''), ['😊']);
    });
  });
}
