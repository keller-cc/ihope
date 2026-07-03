import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/services/auth_session_policy.dart';

void main() {
  group('shouldResetCryptoOnTokenRefresh', () {
    test('same user refresh keeps crypto', () {
      expect(
        shouldResetCryptoOnTokenRefresh(
          priorUserId: 'user-1',
          newUserId: 'user-1',
        ),
        isFalse,
      );
    });

    test('first login has no prior user', () {
      expect(
        shouldResetCryptoOnTokenRefresh(
          priorUserId: null,
          newUserId: 'user-1',
        ),
        isFalse,
      );
    });

    test('account switch resets crypto', () {
      expect(
        shouldResetCryptoOnTokenRefresh(
          priorUserId: 'user-1',
          newUserId: 'user-2',
        ),
        isTrue,
      );
    });
  });
}
