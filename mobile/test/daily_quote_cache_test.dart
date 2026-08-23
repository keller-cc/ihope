import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/services/auth_service.dart';

void main() {
  test('dateKey is calendar day, stable for same local day', () {
    expect(DailyQuote.dateKey(DateTime(2026, 8, 23, 0, 5)), '2026-08-23');
    expect(DailyQuote.dateKey(DateTime(2026, 8, 23, 23, 59)), '2026-08-23');
  });

  test('round-trips stored quote json', () {
    const quote = DailyQuote(
      body: '已加载的金句',
      author: '燕子',
      date: '2026-08-23',
    );
    final again = DailyQuote.fromJson(quote.toJson());
    expect(again.body, quote.body);
    expect(again.author, quote.author);
    expect(again.date, quote.date);
    expect(again.hasContent, isTrue);
  });

  test('empty body is not treated as stored content', () {
    expect(const DailyQuote(body: '   ', date: '2026-08-23').hasContent, isFalse);
  });
}
