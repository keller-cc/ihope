import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ihope/services/device_link_crypto.dart';

void main() {
  test('encrypt decrypt roundtrip', () async {
    const token = 'abc123-link-token';
    const payload = '{"v":1,"keys":{"identity_seed_user_u1":"abc"}}';

    final cipher = await DeviceLinkCrypto.encrypt(token, payload);
    final plain = await DeviceLinkCrypto.decrypt(token, cipher);

    expect(plain, payload);
    expect(jsonDecode(plain), isA<Map<String, dynamic>>());
  });

  test('wrong token fails decrypt', () async {
    const token = 'token-a';
    final cipher = await DeviceLinkCrypto.encrypt(token, 'secret');

    expect(
      () => DeviceLinkCrypto.decrypt('token-b', cipher),
      throwsA(isA<Exception>()),
    );
  });
}
