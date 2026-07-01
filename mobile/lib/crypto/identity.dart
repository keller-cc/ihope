import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 用户身份密钥对（X25519），私钥存 Secure Storage。
class IdentityKeyStore {
  IdentityKeyStore(this._readPrivate, this._writePrivate);

  final Future<Uint8List?> Function() _readPrivate;
  final Future<void> Function(Uint8List privateSeed) _writePrivate;

  SimpleKeyPair? _cached;

  Future<SimpleKeyPair> loadOrCreate() async {
    if (_cached != null) return _cached!;

    final existing = await _readPrivate();
    if (existing != null && existing.length == 32) {
      _cached = await X25519().newKeyPairFromSeed(existing);
      return _cached!;
    }

    final seed = _randomBytes(32);
    await _writePrivate(seed);
    _cached = await X25519().newKeyPairFromSeed(seed);
    return _cached!;
  }

  Future<String> publicKeyBase64() async {
    final keyPair = await loadOrCreate();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rnd.nextInt(256)));
  }
}

SimplePublicKey? tryDecodePublicKey(String base64Key) {
  try {
    return decodePublicKey(base64Key);
  } catch (_) {
    return null;
  }
}

bool isValidIdentityPublicKey(String base64Key) {
  try {
    final bytes = base64Decode(base64Key.trim());
    return bytes.length == 33 && bytes[0] == 0x05;
  } catch (_) {
    return false;
  }
}

bool canUseE2EEWithPeer(String base64Key) {
  return isValidIdentityPublicKey(base64Key);
}

Uint8List identityPublicKeyRawBytes(String base64Key) {
  final bytes = base64Decode(base64Key.trim());
  if (bytes.length == 33 && bytes[0] == 0x05) {
    return Uint8List.fromList(bytes.sublist(1));
  }
  if (bytes.length == 32) {
    return Uint8List.fromList(bytes);
  }
  throw ArgumentError('invalid identity public key length');
}

SimplePublicKey decodePublicKey(String base64Key) {
  return SimplePublicKey(
    identityPublicKeyRawBytes(base64Key),
    type: KeyPairType.x25519,
  );
}
