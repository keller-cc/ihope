import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'e2ee_exception.dart';
import 'identity.dart';

const welcomeWirePrefix = 'e2ee:gw:v1:';
const groupWirePrefix = 'e2ee:g:v1:';
const _welcomeInfo = 'ihope-group-welcome-v1';

/// 群 GMK 本地存储（按 conversation + epoch）。
class GroupEpochStore {
  GroupEpochStore({
    required this.readGmk,
    required this.writeGmk,
  });

  final Future<List<int>?> Function(String conversationId, int epoch) readGmk;
  final Future<void> Function(String conversationId, int epoch, List<int> bytes)
      writeGmk;

  Future<Uint8List?> loadGmk(String conversationId, int epoch) async {
    final raw = await readGmk(conversationId, epoch);
    if (raw == null || raw.length != 32) return null;
    return Uint8List.fromList(raw);
  }

  Future<void> storeGmk(String conversationId, int epoch, Uint8List gmk) {
    return writeGmk(conversationId, epoch, gmk);
  }

  static Uint8List generateGmk() {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
  }
}

/// 群消息与 welcome 包加解密。
class GroupCrypto {
  GroupCrypto({
    required GroupEpochStore store,
    required Future<SimpleKeyPair> Function() loadIdentity,
    required this.myUserId,
  })  : _store = store,
        _loadIdentity = loadIdentity;

  final GroupEpochStore _store;
  final Future<SimpleKeyPair> Function() _loadIdentity;
  final String myUserId;

  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aes = AesGcm.with256bits();

  bool isGroupEncrypted(String value) => value.startsWith(groupWirePrefix);
  bool isWelcomeEncrypted(String value) => value.startsWith(welcomeWirePrefix);

  Future<Uint8List> generateAndStoreGmk(String conversationId, int epoch) async {
    final gmk = GroupEpochStore.generateGmk();
    await _store.storeGmk(conversationId, epoch, gmk);
    return gmk;
  }

  Future<Uint8List> requireGmk(String conversationId, int epoch) async {
    final existing = await _store.loadGmk(conversationId, epoch);
    if (existing != null) return existing;
    throw E2eeException('群密钥尚未就绪（epoch $epoch）');
  }

  Future<String> encryptGroupMessage(
    String conversationId,
    int epoch,
    String plaintext,
  ) async {
    final gmk = await requireGmk(conversationId, epoch);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(gmk),
    );
    return '$groupWirePrefix${base64Encode(box.concatenation())}';
  }

  Future<String> decryptGroupMessage(
    String conversationId,
    int messageEpoch,
    String payload,
  ) async {
    if (!isGroupEncrypted(payload)) return payload;
    final gmk = await _store.loadGmk(conversationId, messageEpoch);
    if (gmk == null) {
      return '[无法解密：缺少 epoch $messageEpoch 群密钥]';
    }
    try {
      final raw = base64Decode(payload.substring(groupWirePrefix.length));
      final box = SecretBox.fromConcatenation(
        raw,
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clear = await _aes.decrypt(box, secretKey: SecretKey(gmk));
      return utf8.decode(clear);
    } catch (_) {
      return '[无法解密]';
    }
  }

  Future<String> buildWelcomeCiphertext({
    required String recipientUserId,
    required String recipientPublicKeyBase64,
    required String conversationId,
    required int epoch,
    required Uint8List gmk,
  }) async {
    if (!canUseE2EEWithPeer(recipientPublicKeyBase64)) {
      throw E2eeException('对方尚未配置加密密钥');
    }
    final plaintext = jsonEncode({
      'conversation_id': conversationId,
      'epoch': epoch,
      'gmk': base64Encode(gmk),
    });
    final key = await _welcomeKey(
      recipientUserId: recipientUserId,
      peerPublicKeyBase64: recipientPublicKeyBase64,
    );
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return '$welcomeWirePrefix${base64Encode(box.concatenation())}';
  }

  Future<({String conversationId, int epoch})> absorbWelcome({
    required String senderUserId,
    required String senderPublicKeyBase64,
    required String ciphertext,
  }) async {
    if (!isWelcomeEncrypted(ciphertext)) {
      throw E2eeException('无效的 welcome 包');
    }
    if (!canUseE2EEWithPeer(senderPublicKeyBase64)) {
      throw E2eeException('发送方尚未配置加密密钥');
    }
    final key = await _welcomeKey(
      recipientUserId: myUserId,
      peerPublicKeyBase64: senderPublicKeyBase64,
    );
    final raw = base64Decode(ciphertext.substring(welcomeWirePrefix.length));
    final box = SecretBox.fromConcatenation(
      raw,
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final clear = await _aes.decrypt(box, secretKey: key);
    final body = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final convId = body['conversation_id'] as String;
    final epoch = body['epoch'] as int;
    final gmk = base64Decode(body['gmk'] as String);
    if (gmk.length != 32) {
      throw E2eeException('welcome 包 GMK 无效');
    }
    await _store.storeGmk(convId, epoch, Uint8List.fromList(gmk));
    return (conversationId: convId, epoch: epoch);
  }

  Future<SecretKey> _welcomeKey({
    required String recipientUserId,
    required String peerPublicKeyBase64,
  }) async {
    final identity = await _loadIdentity();
    final shared = await _x25519.sharedSecretKey(
      keyPair: identity,
      remotePublicKey: decodePublicKey(peerPublicKeyBase64),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode('$_welcomeInfo:$recipientUserId'),
    );
  }
}
