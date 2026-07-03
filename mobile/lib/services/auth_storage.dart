import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../crypto/megolm_rotation_meta.dart';

const _kAccess = 'access_token';
const _kRefresh = 'refresh_token';
const _kDeviceId = 'device_id';
const _kUserProfile = 'user_profile';

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
    await _storage.delete(key: _kUserProfile);
  }

  Future<void> saveUserProfile(Map<String, dynamic> json) async {
    await _storage.write(key: _kUserProfile, value: jsonEncode(json));
  }

  Future<Map<String, dynamic>?> readUserProfile() async {
    final raw = await _storage.read(key: _kUserProfile);
    if (raw == null || raw.isEmpty) return null;
    final json = jsonDecode(raw);
    return json is Map<String, dynamic> ? json : null;
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

  Future<Map<String, String>> readSignalStore(String scope) async {
    final raw = await _storage.read(key: _signalStoreKey(scope));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> writeSignalStore(String scope, Map<String, String> data) async {
    await _storage.write(
      key: _signalStoreKey(scope),
      value: jsonEncode(data),
    );
  }

  Future<void> bindSignalStoreForUser({
    required String userId,
    required String email,
  }) async {
    final userScope = 'user_$userId';
    if (await _storage.read(key: _signalStoreKey(userScope)) != null) {
      return;
    }
    final emailScope = 'email_${email.trim().toLowerCase()}';
    final raw = await _storage.read(key: _signalStoreKey(emailScope));
    if (raw != null) {
      await _storage.write(key: _signalStoreKey(userScope), value: raw);
      await _storage.delete(key: _signalStoreKey(emailScope));
    }
  }

  Future<MegolmRotationMeta?> readMegolmRotationMeta(
    String userId,
    String conversationId,
  ) async {
    final raw = await _storage.read(key: _megolmRotationKey(userId, conversationId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return MegolmRotationMeta.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMegolmRotationMeta(
    String userId,
    String conversationId,
    MegolmRotationMeta meta,
  ) async {
    await _storage.write(
      key: _megolmRotationKey(userId, conversationId),
      value: jsonEncode(meta.toJson()),
    );
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

  Future<void> clearGroupGmk(
    String ownerUserId,
    String conversationId,
    int epoch,
  ) async {
    await _storage.delete(
      key: _groupGmkKey(ownerUserId, conversationId, epoch),
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
    await removeArchivedConversations(userId, {conversationId});
  }

  Future<void> removeArchivedConversations(
    String userId,
    Set<String> conversationIds,
  ) async {
    if (conversationIds.isEmpty) return;
    final list = await readArchivedConversationsRaw(userId);
    final next = list
        .where((e) => !conversationIds.contains(e['id'] as String? ?? ''))
        .toList(growable: false);
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

  Future<void> saveConversationListSnapshot(
    String userId,
    List<Map<String, dynamic>> conversations,
  ) async {
    await _storage.write(
      key: _conversationListKey(userId),
      value: jsonEncode(conversations),
    );
  }

  Future<List<Map<String, dynamic>>> readConversationListSnapshot(
    String userId,
  ) async {
    final raw = await _storage.read(key: _conversationListKey(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<DateTime?> readConversationReadAt(
    String userId,
    String conversationId,
  ) async {
    final raw = await _storage.read(
      key: _readCursorKey(userId, conversationId),
    );
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> writeConversationReadAt(
    String userId,
    String conversationId,
    DateTime readAt,
  ) async {
    await _storage.write(
      key: _readCursorKey(userId, conversationId),
      value: readAt.toUtc().toIso8601String(),
    );
  }

  Future<String?> readAnnouncementReadId(
    String userId,
    String conversationId,
  ) async {
    return _storage.read(
      key: _announcementReadKey(userId, conversationId),
    );
  }

  Future<Set<String>> readAnnouncementReadIds(
    String userId,
    String conversationId,
  ) async {
    final raw = await _storage.read(
      key: _announcementReadIdsKey(userId, conversationId),
    );
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list.map((e) => e as String).toSet();
      } catch (_) {}
    }

    final legacy = await readAnnouncementReadId(userId, conversationId);
    if (legacy != null && legacy.isNotEmpty) {
      final migrated = {legacy};
      await writeAnnouncementReadIds(userId, conversationId, migrated);
      await _storage.delete(key: _announcementReadKey(userId, conversationId));
      return migrated;
    }
    return {};
  }

  Future<void> writeAnnouncementReadIds(
    String userId,
    String conversationId,
    Set<String> messageIds,
  ) async {
    await _storage.write(
      key: _announcementReadIdsKey(userId, conversationId),
      value: jsonEncode(messageIds.toList()),
    );
  }

  Future<void> addAnnouncementReadId(
    String userId,
    String conversationId,
    String messageId,
  ) async {
    final ids = await readAnnouncementReadIds(userId, conversationId);
    if (ids.contains(messageId)) return;
    ids.add(messageId);
    await writeAnnouncementReadIds(userId, conversationId, ids);
  }

  Future<Set<String>> readHiddenConversations(String userId) async {
    final raw = await _storage.read(key: _hiddenConversationsKey(userId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> addHiddenConversation(
    String userId,
    String conversationId,
  ) async {
    final hidden = await readHiddenConversations(userId);
    if (hidden.contains(conversationId)) return;
    hidden.add(conversationId);
    await _storage.write(
      key: _hiddenConversationsKey(userId),
      value: jsonEncode(hidden.toList()),
    );
  }

  Future<void> removeHiddenConversation(
    String userId,
    String conversationId,
  ) async {
    final hidden = await readHiddenConversations(userId);
    if (!hidden.remove(conversationId)) return;
    await _storage.write(
      key: _hiddenConversationsKey(userId),
      value: jsonEncode(hidden.toList()),
    );
  }

  String _archivedConversationsKey(String userId) =>
      'archived_conversations_$userId';

  String _conversationListKey(String userId) => 'conversation_list_$userId';

  String _hiddenConversationsKey(String userId) =>
      'hidden_conversations_$userId';

  String _readCursorKey(String userId, String conversationId) =>
      'read_cursor_${userId}_$conversationId';

  String _announcementReadKey(String userId, String conversationId) =>
      'announcement_read_${userId}_$conversationId';

  String _announcementReadIdsKey(String userId, String conversationId) =>
      'announcement_read_ids_${userId}_$conversationId';

  String _messageCacheKey(String userId, String conversationId) =>
      'message_cache_${userId}_$conversationId';

  String _memberDirectoryKey(String userId, String conversationId) =>
      'member_directory_${userId}_$conversationId';

  Future<void> saveMemberDirectory(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> members,
  ) async {
    await _storage.write(
      key: _memberDirectoryKey(userId, conversationId),
      value: jsonEncode(members),
    );
  }

  Future<List<Map<String, dynamic>>> readMemberDirectory(
    String userId,
    String conversationId,
  ) async {
    final raw =
        await _storage.read(key: _memberDirectoryKey(userId, conversationId));
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _pinnedKey(String userId) => 'pinned_conversations_$userId';

  String _groupGmkKey(String ownerUserId, String conversationId, int epoch) =>
      'group_gmk_${ownerUserId}_${conversationId}_$epoch';

  String _userIdentityKey(String userId) => 'identity_seed_user_$userId';

  String _emailIdentityKey(String email) =>
      'identity_seed_email_${email.trim().toLowerCase()}';

  String _sessionKey(String ownerUserId, String peerUserId) =>
      'dm_session_${ownerUserId}_$peerUserId';

  String _signalStoreKey(String scope) => 'signal_store_$scope';

  String _chatSearchHistoryKey(String userId, String conversationId) =>
      'chat_search_history_${userId}_$conversationId';

  Future<List<String>> readChatSearchHistory(
    String userId,
    String conversationId,
  ) async {
    final raw = await _storage.read(
      key: _chatSearchHistoryKey(userId, conversationId),
    );
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeChatSearchHistory(
    String userId,
    String conversationId,
    List<String> queries,
  ) async {
    await _storage.write(
      key: _chatSearchHistoryKey(userId, conversationId),
      value: jsonEncode(queries),
    );
  }

  String _megolmRotationKey(String userId, String conversationId) =>
      'megolm_rotation_${userId}_$conversationId';

  Future<Uint8List?> _readSeed(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    return Uint8List.fromList(base64Decode(raw));
  }

  Future<void> _writeSeed(String key, Uint8List seed) async {
    await _storage.write(key: key, value: base64Encode(seed));
  }
}
