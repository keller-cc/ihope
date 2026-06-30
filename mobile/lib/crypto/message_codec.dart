import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'identity.dart';
import 'e2ee_exception.dart';

const _sessionInfo = 'ihope-dm-v1';
const _wirePrefix = 'e2ee:v1:';

/// 单聊消息加解密（X25519 ECDH + HKDF + AES-GCM）。
class MessageCodec {
  MessageCodec({
    required Future<SimpleKeyPair> Function() loadIdentity,
    required Future<List<int>?> Function(String peerUserId) readSession,
    required Future<String?> Function(String peerUserId) readSessionPeerKey,
    required Future<void> Function(
      String peerUserId,
      List<int> keyBytes,
      String peerPublicKeyBase64,
    ) writeSession,
    required Future<void> Function(String peerUserId) clearSession,
  })  : _loadIdentity = loadIdentity,
        _readSession = readSession,
        _readSessionPeerKey = readSessionPeerKey,
        _writeSession = writeSession,
        _clearSession = clearSession;

  final Future<SimpleKeyPair> Function() _loadIdentity;
  final Future<List<int>?> Function(String peerUserId) _readSession;
  final Future<String?> Function(String peerUserId) _readSessionPeerKey;
  final Future<void> Function(
    String peerUserId,
    List<int> keyBytes,
    String peerPublicKeyBase64,
  ) _writeSession;
  final Future<void> Function(String peerUserId) _clearSession;

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aes = AesGcm.with256bits();

  bool isEncrypted(String value) => value.startsWith(_wirePrefix);

  Future<String> encrypt({
    required String peerUserId,
    required String peerPublicKeyBase64,
    required String plaintext,
  }) async {
    if (!canUseE2EEWithPeer(peerPublicKeyBase64)) {
      throw E2eeException('对方尚未配置加密密钥，请让对方重新登录后再试');
    }
    final sessionKey = await _sessionKey(peerUserId, peerPublicKeyBase64);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: sessionKey,
    );
    return '$_wirePrefix${base64Encode(box.concatenation())}';
  }

  Future<String> decrypt({
    required String peerUserId,
    required String peerPublicKeyBase64,
    required String payload,
  }) async {
    if (!isEncrypted(payload)) return payload;
    if (!canUseE2EEWithPeer(peerPublicKeyBase64)) {
      return '[无法解密：对方未配置加密密钥]';
    }
    final first = await _tryDecrypt(peerUserId, peerPublicKeyBase64, payload);
    if (first != null) return first;
    await _clearSession(peerUserId);
    final second = await _tryDecrypt(peerUserId, peerPublicKeyBase64, payload);
    return second ?? '[无法解密]';
  }

  Future<String?> _tryDecrypt(
    String peerUserId,
    String peerPublicKeyBase64,
    String payload,
  ) async {
    try {
      final sessionKey = await _sessionKey(peerUserId, peerPublicKeyBase64);
      final raw = base64Decode(payload.substring(_wirePrefix.length));
      final box = SecretBox.fromConcatenation(
        raw,
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clear = await _aes.decrypt(box, secretKey: sessionKey);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _sessionKey(
    String peerUserId,
    String peerPublicKeyBase64,
  ) async {
    final cached = await _readSession(peerUserId);
    final cachedPub = await _readSessionPeerKey(peerUserId);
    if (cached != null &&
        cached.length == 32 &&
        cachedPub == peerPublicKeyBase64) {
      return SecretKey(cached);
    }

    final identity = await _loadIdentity();
    final shared = await _x25519.sharedSecretKey(
      keyPair: identity,
      remotePublicKey: decodePublicKey(peerPublicKeyBase64),
    );
    final derived = await _hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode(_sessionInfo),
    );
    final bytes = await derived.extractBytes();
    await _writeSession(peerUserId, bytes, peerPublicKeyBase64);
    return derived;
  }
}
