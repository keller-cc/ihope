import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/utils/text_search.dart';

void main() {
  test('textMatchesQuery is case insensitive', () {
    expect(textMatchesQuery('Hello World', 'hello'), isTrue);
    expect(textMatchesQuery('Hello World', 'WORLD'), isTrue);
    expect(textMatchesQuery('Hello World', 'xyz'), isFalse);
  });

  test('textMatchesQuery matches empty query', () {
    expect(textMatchesQuery('anything', ''), isTrue);
    expect(textMatchesQuery('anything', '   '), isTrue);
  });
}
