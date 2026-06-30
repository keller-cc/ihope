import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const _kAccess = 'access_token';
const _kRefresh = 'refresh_token';
const _kDeviceId = 'device_id';

class AuthStorage {
  AuthStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _uuid = Uuid();

  Future<String> deviceId() async {
    var id = await _storage.read(key: _kDeviceId);
    if (id == null || id.isEmpty) {
      id = 'flutter-${_uuid.v4()}';
      await _storage.write(key: _kDeviceId, value: id);
    }
    return id;
  }

  Future<String?> accessToken() => _storage.read(key: _kAccess);

  Future<String?> refreshToken() => _storage.read(key: _kRefresh);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    await _storage.write(key: _kRefresh, value: refreshToken);
  }

  /// 登出只清 token，保留各账号身份密钥与 device_id。
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  Future<Uint8List?> readIdentitySeedForUser(String userId) =>
      _readSeed(_userIdentityKey(userId));

  Future<void> writeIdentitySeedForUser(String userId, Uint8List seed) =>
      _writeSeed(_userIdentityKey(userId), seed);

  Future<Uint8List?> readIdentitySeedForEmail(String email) =>
      _readSeed(_emailIdentityKey(email));

  Future<void> writeIdentitySeedForEmail(String email, Uint8List seed) =>
      _writeSeed(_emailIdentityKey(email), seed);

  /// 登录后把注册阶段的 email 密钥绑定到 userId。
  Future<void> bindIdentityForUser({
    required String userId,
    required String email,
  }) async {
    if (await readIdentitySeedForUser(userId) != null) {
      return;
    }

    final emailSeed = await readIdentitySeedForEmail(email);
    if (emailSeed != null) {
      await writeIdentitySeedForUser(userId, emailSeed);
      await _storage.delete(key: _emailIdentityKey(email));
    }
  }

  Future<List<int>?> readSessionKey(String ownerUserId, String peerUserId) async {
    final raw = await _storage.read(key: _sessionKey(ownerUserId, peerUserId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final key = decoded['key'] as String?;
        if (key != null && key.isNotEmpty) {
          return base64Decode(key);
        }
      }
    } catch (_) {}
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readSessionPeerKey(String ownerUserId, String peerUserId) async {
    final raw = await _storage.read(key: _sessionKey(ownerUserId, peerUserId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded['peer_pub'] as String?;
      }
    } catch (_) {}
    return null;
  }

  Future<void> writeSessionKey(
    String ownerUserId,
    String peerUserId,
    List<int> keyBytes, {
    required String peerPublicKey,
  }) async {
    await _storage.write(
      key: _sessionKey(ownerUserId, peerUserId),
      value: jsonEncode({
        'key': base64Encode(keyBytes),
        'peer_pub': peerPublicKey,
      }),
    );
  }

  Future<void> clearSessionKey(String ownerUserId, String peerUserId) async {
    await _storage.delete(key: _sessionKey(ownerUserId, peerUserId));
  }

  Future<List<int>?> readGroupGmk(
    String ownerUserId,
    String conversationId,
    int epoch,
  ) async {
    final raw = await _storage.read(
      key: _groupGmkKey(ownerUserId, conversationId, epoch),
    );
    if (raw == null || raw.isEmpty) return null;
    return base64Decode(raw);
  }

  Future<void> writeGroupGmk(
    String ownerUserId,
    String conversationId,
    int epoch,
    List<int> bytes,
  ) async {
    await _storage.write(
      key: _groupGmkKey(ownerUserId, conversationId, epoch),
      value: base64Encode(bytes),
    );
  }

  Future<List<String>> readPinnedConversations(String userId) async {
    final raw = await _storage.read(key: _pinnedKey(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writePinnedConversations(
    String userId,
    List<String> conversationIds,
  ) async {
    await _storage.write(
      key: _pinnedKey(userId),
      value: jsonEncode(conversationIds),
    );
  }

  Future<void> saveArchivedConversation(
    String userId,
    Map<String, dynamic> conversation,
  ) async {
    final list = await readArchivedConversationsRaw(userId);
    final id = conversation['id'] as String;
    list.removeWhere((e) => e['id'] == id);
    list.insert(0, conversation);
    await _storage.write(
      key: _archivedConversationsKey(userId),
      value: jsonEncode(list),
    );
  }

  Future<List<Map<String, dynamic>>> readArchivedConversationsRaw(
    String userId,
  ) async {
    final raw = await _storage.read(key: _archivedConversationsKey(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeArchivedConversation(
    String userId,
    String conversationId,
  ) async {
    final list = await readArchivedConversationsRaw(userId);
    final next =
        list.where((e) => e['id'] != conversationId).toList(growable: false);
    if (next.length == list.length) return;
    await _storage.write(
      key: _archivedConversationsKey(userId),
      value: jsonEncode(next),
    );
  }

  Future<void> saveMessageCache(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    await _storage.write(
      key: _messageCacheKey(userId, conversationId),
      value: jsonEncode(messages),
    );
  }

  Future<List<Map<String, dynamic>>> readMessageCache(
    String userId,
    String conversationId,
  ) async {
    final raw = await _storage.read(key: _messageCacheKey(userId, conversationId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  String _archivedConversationsKey(String userId) =>
      'archived_conversations_$userId';

  String _messageCacheKey(String userId, String conversationId) =>
      'message_cache_${userId}_$conversationId';

  String _pinnedKey(String userId) => 'pinned_conversations_$userId';

  String _groupGmkKey(String ownerUserId, String conversationId, int epoch) =>
      'group_gmk_${ownerUserId}_${conversationId}_$epoch';

  String _userIdentityKey(String userId) => 'identity_seed_user_$userId';

  String _emailIdentityKey(String email) =>
      'identity_seed_email_${email.trim().toLowerCase()}';

  String _sessionKey(String ownerUserId, String peerUserId) =>
      'dm_session_${ownerUserId}_$peerUserId';

  Future<Uint8List?> _readSeed(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    return Uint8List.fromList(base64Decode(raw));
  }

  Future<void> _writeSeed(String key, Uint8List seed) async {
    await _storage.write(key: key, value: base64Encode(seed));
  }
}
