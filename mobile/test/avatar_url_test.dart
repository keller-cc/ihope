import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/utils/avatar_url.dart';

void main() {
  test('resolveAvatarUrl rewrites localhost to api base host', () {
    expect(
      resolveAvatarUrl('http://localhost:8080/api/avatars/u1.png'),
      'http://10.0.2.2:8080/api/avatars/u1.png',
    );
  });

  test('resolveAvatarUrl resolves relative path', () {
    expect(
      resolveAvatarUrl('/api/avatars/u1.png'),
      'http://10.0.2.2:8080/api/avatars/u1.png',
    );
  });

  test('resolveAvatarUrl resolves relative path with cache buster', () {
    expect(
      resolveAvatarUrl('/api/avatars/g1.png?v=1710000000'),
      'http://10.0.2.2:8080/api/avatars/g1.png?v=1710000000',
    );
  });

  test('resolveAvatarUrl returns null for empty', () {
    expect(resolveAvatarUrl(null), isNull);
    expect(resolveAvatarUrl(''), isNull);
  });
}
