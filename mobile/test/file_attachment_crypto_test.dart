import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/services/file_attachment_crypto.dart';

void main() {
  test('encrypt decrypt roundtrip', () async {
    final key = await FileAttachmentCrypto.generateKey();
    const plain = [1, 2, 3, 4, 5];
    final encrypted = await FileAttachmentCrypto.encrypt(key, plain);
    final decrypted = await FileAttachmentCrypto.decrypt(key, encrypted);
    expect(decrypted, plain);
  });

  test('key b64 roundtrip', () async {
    final key = await FileAttachmentCrypto.generateKey();
    final b64 = FileAttachmentCrypto.keyToB64(key);
    expect(FileAttachmentCrypto.keyFromB64(b64), key);
  });
}
