import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// 设备链接同步包加解密（token → HKDF → AES-GCM）。
class DeviceLinkCrypto {
  DeviceLinkCrypto._();

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aes = AesGcm.with256bits();
  static const _info = 'ihope-device-link-v1';

  static Future<String> encrypt(String token, String plaintext) async {
    final key = await _deriveKey(token);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return base64Encode(box.concatenation());
  }

  static Future<String> decrypt(String token, String ciphertextB64) async {
    final key = await _deriveKey(token);
    final raw = base64Decode(ciphertextB64);
    final box = SecretBox.fromConcatenation(
      raw,
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  static Future<SecretKey> _deriveKey(String token) {
    return _hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(token)),
      info: utf8.encode(_info),
    );
  }
}
