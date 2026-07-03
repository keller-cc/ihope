import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 附件文件客户端 AES-GCM 加解密（每文件独立密钥，密钥经 E2EE 消息传递）。
class FileAttachmentCrypto {
  FileAttachmentCrypto._();

  static final _aes = AesGcm.with256bits();
  static final _random = Random.secure();

  static Future<List<int>> generateKey() async {
    final key = await _aes.newSecretKey();
    return await key.extractBytes();
  }

  static Future<List<int>> encrypt(List<int> keyBytes, List<int> plaintext) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(keyBytes),
    );
    return box.concatenation();
  }

  static Future<List<int>> decrypt(List<int> keyBytes, List<int> ciphertext) async {
    final box = SecretBox.fromConcatenation(
      ciphertext,
      nonceLength: 12,
      macLength: 16,
    );
    return await _aes.decrypt(box, secretKey: SecretKey(keyBytes));
  }

  static String keyToB64(List<int> key) => base64Encode(key);

  static List<int> keyFromB64(String b64) => base64Decode(b64);

  static Uint8List randomNonce([int length = 12]) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }
}
