import 'dart:async';
import 'dart:convert';

import '../crypto/chat_crypto.dart';
import '../crypto/e2ee_exception.dart';
import '../crypto/identity.dart';
import '../crypto/signal/signal_dm_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../utils/media_local_cache.dart';
import '../utils/media_payload.dart';
import 'api_client.dart';
import 'auth_storage.dart';
import 'conversation_service.dart';
import 'group_key_service.dart';
import 'signal_kds_service.dart';
import 'ws_service.dart';

class AuthService {
  AuthService({ApiClient? api, AuthStorage? storage, WsService? ws})
      : api = api ?? ApiClient(),
        storage = storage ?? AuthStorage(),
        ws = ws ?? WsService() {
    this.api.onUnauthorized = _tryRefreshTokens;
    this.ws.resolveToken = ensureValidAccessToken;
  }

  final ApiClient api;
  final AuthStorage storage;
  final WsService ws;
  late final ConversationService conversations = ConversationService(api);

  User? currentUser;
  ChatCrypto? _crypto;
  SignalDmService? _signalDm;
  GroupKeyService? _groupKeys;
  final Map<String, ConversationItem> _conversationCache = {};
  final Map<String, Map<String, ConversationMember>> _memberDirectories = {};
  final Map<String, List<ChatMessage>> _messagesMem = {};
  final Set<String> _memberDirectorySynced = {};
  String? _openConversationId;
  final Map<String, int> _unreadCounts = {};
  final Map<String, DateTime> _removalUiClaimed = {};

  DateTime? _accessExpiresAt;
  Future<bool>? _refreshInFlight;

  static const _refreshSkew = Duration(minutes: 2);

  /// 群 GMK 就绪（当前打开的会话可据此重新解密）。
  Stream<String> get onGroupKeyReady => groupKeys.onKeysReady;

  GroupKeyService get groupKeys {
    return _groupKeys ??= GroupKeyService(
      conversations: conversations,
      storage: storage,
      ws: ws,
      crypto: () => chatCrypto,
      refreshConversation: _refreshConversation,
      getCurrentUser: () => currentUser,
      getOpenConversationId: () => _openConversationId,
      getCachedConversation: (id) => _conversationCache[id],
      cacheConversation: _cacheConversation,
    );
  }

  ChatCrypto get chatCrypto {
    final crypto = _crypto;
    if (crypto == null) {
      throw StateError('加密模块尚未就绪，请重新登录');
    }
    return crypto;
  }

  Future<SignalDmService> _ensureSignalDm() async {
    final user = currentUser;
    if (user == null) throw StateError('not logged in');
    if (_signalDm != null) return _signalDm!;
    final deviceId = await storage.deviceId();
    _signalDm = SignalDmService(
      kds: SignalKdsService(api),
      myUserId: user.id,
      deviceId: deviceId,
      readStore: () => storage.readSignalStore('user_${user.id}'),
      writeStore: (data) => storage.writeSignalStore('user_${user.id}', data),
    );
    return _signalDm!;
  }

  Future<ChatCrypto> _buildChatCrypto() async {
    final user = currentUser!;
    final signal = await _ensureSignalDm();
    return createChatCrypto(
      myUserId: user.id,
      signal: signal,
      readGroupGmk: (convId, epoch) =>
          storage.readGroupGmk(user.id, convId, epoch),
      writeGroupGmk: (convId, epoch, bytes) =>
          storage.writeGroupGmk(user.id, convId, epoch, bytes),
    );
  }

  Future<bool> restoreSession() async {
    final token = await storage.accessToken();
    if (token == null || token.isEmpty) {
      return false;
    }
    api.setAccessToken(token);
    _accessExpiresAt = _expiryFromJwt(token);
    try {
      await refreshCurrentUser();
    } catch (_) {
      if (!await _tryRefreshTokens()) {
        await _disconnectRealtime();
        await storage.clear();
        api.setAccessToken(null);
        _crypto = null;
    _signalDm = null;
        _accessExpiresAt = null;
        return false;
      }
      await refreshCurrentUser();
    }
    try {
      final identityRotated = await _ensureSignalIdentity();
      _crypto = await _buildChatCrypto();
      await _connectRealtime();
      if (identityRotated) {
        await groupKeys.onIdentityRotated();
      }
      return true;
    } catch (_) {
      await _disconnectRealtime();
      await storage.clear();
      api.setAccessToken(null);
      _crypto = null;
    _signalDm = null;
      _accessExpiresAt = null;
      return false;
    }
  }

  Future<User> refreshCurrentUser() async {
    final data = await api.getJson('/api/users/me');
    currentUser = User.fromJson(data);
    return currentUser!;
  }

  Future<User> login({
    required String email,
    required String password,
  }) async {
    final deviceId = await storage.deviceId();
    final data = await api.postJson('/api/auth/login', body: {
      'email': email.trim(),
      'password': password,
      'device_id': deviceId,
      'device_name': 'Flutter',
    });
    await _saveTokenResponse(data);
    final identityRotated = await _ensureSignalIdentity();
    _crypto = await _buildChatCrypto();
    await _connectRealtime();
    if (identityRotated) {
      await groupKeys.onIdentityRotated();
    }
    return currentUser!;
  }

  Future<User> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final deviceId = await storage.deviceId();
    final preRegisterDm = SignalDmService(
      kds: SignalKdsService(api),
      myUserId: 'pending',
      deviceId: deviceId,
      readStore: () => storage.readSignalStore('email_$normalizedEmail'),
      writeStore: (data) =>
          storage.writeSignalStore('email_$normalizedEmail', data),
    );
    final pubKey = await preRegisterDm.identityPublicKeyBase64();
    await api.postJson('/api/auth/register', body: {
      'email': email.trim(),
      'username': username.trim(),
      'password': password,
      'identity_public_key': pubKey,
    });
    return login(email: email, password: password);
  }

  Future<User> updateUsername(String username) async {
    final data = await api.patchJson('/api/users/me', body: {
      'username': username.trim(),
    });
    currentUser = User.fromJson(data);
    return currentUser!;
  }

  Future<User> uploadAvatar(List<int> bytes, {String filename = 'avatar.jpg'}) async {
    final data = await api.postMultipart(
      '/api/users/me/avatar',
      field: 'avatar',
      filename: filename,
      bytes: bytes,
    );
    currentUser = User.fromJson(data);
    return currentUser!;
  }

  Future<ConversationItem> updateGroupName(
    ConversationItem conversation,
    String name,
  ) async {
    final conv = await conversations.updateGroupName(conversation.id, name);
    _cacheConversation(conv);
    return conv;
  }

  Future<ConversationItem> uploadGroupAvatar(
    ConversationItem conversation,
    List<int> bytes, {
    String filename = 'avatar.jpg',
  }) async {
    final conv = await conversations.uploadGroupAvatar(
      conversation.id,
      bytes,
      filename: filename,
    );
    _cacheConversation(conv);
    return conv;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await api.postJson('/api/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    await logout();
  }

  Future<String?> forgotPassword(String email) async {
    final data = await api.postJson('/api/auth/forgot-password', body: {
      'email': email.trim(),
    });
    return data['dev_reset_token'] as String?;
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await api.postJson('/api/auth/reset-password', body: {
      'token': token.trim(),
      'password': password,
    });
  }

  Future<void> logout() async {
    await _disconnectRealtime();
    await storage.clear();
    api.setAccessToken(null);
    currentUser = null;
    _crypto = null;
    _signalDm = null;
    _conversationCache.clear();
    _messagesMem.clear();
    _memberDirectories.clear();
    _memberDirectorySynced.clear();
    _accessExpiresAt = null;
  }

  /// 供 WS 重连与 API 401 拦截器使用：必要时 refresh 后返回有效 token。
  Future<String?> ensureValidAccessToken() async {
    if (_shouldRefreshProactively()) {
      final ok = await _tryRefreshTokens();
      if (!ok) return null;
    }
    return storage.accessToken();
  }

  Future<bool> _tryRefreshTokens() async {
    if (_refreshInFlight != null) {
      return _refreshInFlight!;
    }

    final refresh = await storage.refreshToken();
    if (refresh == null || refresh.isEmpty) {
      return false;
    }

    _refreshInFlight = _doRefreshTokens(refresh);
    try {
      return await _refreshInFlight!;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<bool> _doRefreshTokens(String refreshToken) async {
    try {
      final deviceId = await storage.deviceId();
      final data = await api.postJsonPublic('/api/auth/refresh', body: {
        'refresh_token': refreshToken,
        'device_id': deviceId,
      });
      await _saveTokenResponse(data);
      final access = await storage.accessToken();
      if (access != null && access.isNotEmpty) {
        if (ws.isConnected) {
          ws.updateAccessToken(access);
        } else {
          await ws.reconnect(access);
        }
      }
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _shouldRefreshProactively() {
    if (_accessExpiresAt == null) return false;
    return DateTime.now().isAfter(_accessExpiresAt!.subtract(_refreshSkew));
  }

  DateTime? _expiryFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is int) {
        return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveTokenResponse(Map<String, dynamic> data) async {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    await storage.saveTokens(accessToken: access, refreshToken: refresh);
    api.setAccessToken(access);
    currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
    _crypto = null;
    _signalDm = null;
    _accessExpiresAt = _expiryFromJwt(access);
    final expiresIn = data['expires_in'];
    if (expiresIn is int) {
      _accessExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    }
  }

  Future<String?> accessToken() => storage.accessToken();

  Future<List<String>> pinnedConversationIds() async {
    final user = currentUser;
    if (user == null) return [];
    return storage.readPinnedConversations(user.id);
  }

  Future<bool> isConversationPinned(String conversationId) async {
    final ids = await pinnedConversationIds();
    return ids.contains(conversationId);
  }

  Future<void> setConversationPinned(
    String conversationId, {
    required bool pinned,
  }) async {
    final user = currentUser;
    if (user == null) return;
    var ids = await storage.readPinnedConversations(user.id);
    if (pinned) {
      ids.remove(conversationId);
      ids.insert(0, conversationId);
    } else {
      ids.remove(conversationId);
    }
    await storage.writePinnedConversations(user.id, ids);
  }

  void setOpenConversation(String? conversationId) {
    _openConversationId = conversationId;
  }

  bool isConversationOpen(String conversationId) =>
      _openConversationId == conversationId;

  Future<DateTime?> readAtFor(String conversationId) async {
    final me = currentUser;
    if (me == null) return null;
    return storage.readConversationReadAt(me.id, conversationId);
  }

  int countUnreadInThread(
    List<ChatMessage> messages, {
    DateTime? readAt,
  }) {
    final me = currentUser;
    if (me == null) return 0;
    return _countUnread(messages, me.id, readAt);
  }

  int? firstUnreadIndexInThread(
    List<ChatMessage> messages, {
    DateTime? readAt,
  }) {
    final me = currentUser;
    if (me == null) return null;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.senderId == me.id) continue;
      if (readAt == null || m.createdAt.isAfter(readAt)) return i;
    }
    return null;
  }

  Future<void> markConversationRead(
    String conversationId, {
    DateTime? upTo,
  }) async {
    final me = currentUser;
    if (me == null) return;
    final at = upTo ?? DateTime.now();
    await storage.writeConversationReadAt(me.id, conversationId, at);
    _unreadCounts[conversationId] = 0;
  }

  Future<int> unreadCountFor(String conversationId) async {
    if (_unreadCounts.containsKey(conversationId)) {
      return _unreadCounts[conversationId]!;
    }
    final me = currentUser;
    if (me == null) return 0;
    final readAt = await storage.readConversationReadAt(me.id, conversationId);
    final messages = await loadCachedMessages(conversationId);
    final count = _countUnread(messages, me.id, readAt);
    _unreadCounts[conversationId] = count;
    return count;
  }

  Future<Map<String, int>> unreadCountsFor(
    Iterable<String> conversationIds,
  ) async {
    final out = <String, int>{};
    for (final id in conversationIds) {
      out[id] = await unreadCountFor(id);
    }
    return out;
  }

  int _countUnread(
    List<ChatMessage> messages,
    String meId,
    DateTime? readAt,
  ) {
    var count = 0;
    for (final m in messages) {
      if (m.senderId == meId) continue;
      if (readAt == null || m.createdAt.isAfter(readAt)) {
        count++;
      }
    }
    return count;
  }

  Future<void> noteIncomingMessage(ChatMessage msg) async {
    if (_openConversationId == msg.conversationId) {
      return;
    }
    final me = currentUser;
    if (me == null || msg.senderId == me.id) return;
    _unreadCounts[msg.conversationId] =
        (_unreadCounts[msg.conversationId] ?? 0) + 1;
  }

  void resetUnreadCounts() => _unreadCounts.clear();

  /// 离线期间的消息不会经 WS 写入本地；根据会话 lastMessage 拉取并合并。
  Future<void> syncMissedMessages(List<ConversationItem> items) async {
    final me = currentUser;
    if (me == null) return;

    final convApi = conversations;
    var synced = false;
    for (final conv in items) {
      if (conv.isArchived) continue;
      final last = conv.lastMessage;
      if (last == null) continue;

      final readAt =
          await storage.readConversationReadAt(me.id, conv.id);
      if (readAt != null && !last.createdAt.isAfter(readAt)) continue;

      final cached = await loadCachedMessages(conv.id);
      if (cached.any((m) => m.id == last.id)) continue;

      try {
        final remote = await convApi.listMessages(conv.id, limit: 100);
        final merged = _mergeMessageCaches(remote, cached);
        if (merged.isNotEmpty) {
          await cacheMessages(conv.id, merged);
          synced = true;
        }
      } catch (_) {}
    }
    if (synced) resetUnreadCounts();
  }

  List<ChatMessage> _mergeMessageCaches(
    List<ChatMessage> remote,
    List<ChatMessage> local,
  ) {
    final byId = {for (final m in remote) m.id: m};
    for (final cached in local) {
      final hit = byId[cached.id];
      if (hit == null) {
        byId[cached.id] = cached;
      } else {
        final pt = cached.plaintext;
        if (pt != null &&
            pt.isNotEmpty &&
            !ChatMessage.isDecryptPlaceholder(pt) &&
            !ChatMessage.isDecryptFailure(pt)) {
          byId[cached.id] = hit.copyWith(plaintext: pt);
        }
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> hideConversationFromList(String conversationId) async {
    final me = currentUser;
    if (me == null) return;
    await setConversationPinned(conversationId, pinned: false);
    await storage.addHiddenConversation(me.id, conversationId);
    _unreadCounts.remove(conversationId);
  }

  Future<void> restoreConversationToList(String conversationId) async {
    final me = currentUser;
    if (me == null) return;
    await storage.removeHiddenConversation(me.id, conversationId);
  }

  Future<Set<String>> hiddenConversationIds() async {
    final me = currentUser;
    if (me == null) return {};
    return storage.readHiddenConversations(me.id);
  }

  List<ConversationItem> filterVisibleConversations(
    List<ConversationItem> items,
    Set<String> hiddenIds,
  ) {
    if (hiddenIds.isEmpty) return items;
    return items.where((c) => !hiddenIds.contains(c.id)).toList();
  }

  Future<ChatMessage> sendChatMessage(
    ConversationItem conversation,
    String plaintext, {
    String type = 'text',
  }) async {
    if (conversation.isArchived) {
      throw StateError('已退出群聊，无法发送消息');
    }
    final me = currentUser;
    if (me == null || !isValidIdentityPublicKey(me.identityPublicKey)) {
      throw E2eeException('本机加密密钥未就绪，请退出后重新登录');
    }
    var fresh = await _refreshConversation(conversation);
    if (fresh.type == 'group') {
      fresh = await groupKeys.maybeRotateBeforeSend(fresh);
      await groupKeys.ensureReadyForSend(fresh);
    }
    final payload = await chatCrypto.encryptOutgoing(fresh, plaintext);
    if (!chatCrypto.isEncryptedPayload(payload)) {
      throw E2eeException('消息未能加密，已取消发送');
    }
    final msg = await conversations.sendMessage(
      fresh.id,
      payload,
      type: type,
    );
    if (fresh.type == 'group') {
      await groupKeys.recordGroupMessageSent(fresh.id);
    }
    var sent = msg.copyWith(plaintext: plaintext);
    if (type == 'image' || type == 'audio' || type == 'file') {
      final compact = await MediaLocalCache.persistPlaintext(msg.id, plaintext);
      if (compact != null) sent = msg.copyWith(plaintext: compact);
    }
    await upsertCachedMessage(fresh.id, sent);
    return sent;
  }

  Future<ConversationItem> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final me = currentUser;
    if (me == null || !isValidIdentityPublicKey(me.identityPublicKey)) {
      throw E2eeException('本机加密密钥未就绪，请退出后重新登录');
    }
    final conv = await conversations.createGroupChat(
      name: name,
      memberIds: memberIds,
    );
    _cacheConversation(conv);
    final gmk = await chatCrypto.initGroupEpoch(conv.id, conv.epoch);
    await groupKeys.publishEpochKeys(conv, gmk);
    await groupKeys.resetRotationMeta(conv.id);
    return conv;
  }

  Future<ConversationItem> addGroupMembers(
    ConversationItem conversation,
    List<String> memberIds,
  ) async {
    final result = await conversations.addMembers(conversation.id, memberIds);
    final updated = result.conversation.copyWith(epoch: result.epoch);
    _cacheConversation(updated);
    final gmk = await chatCrypto.rotateGroupEpoch(updated.id, result.epoch);
    await groupKeys.publishEpochKeys(updated, gmk);
    await groupKeys.resetRotationMeta(updated.id);
    return updated;
  }

  Future<ConversationItem> removeGroupMember(
    ConversationItem conversation,
    String targetUserId,
  ) async {
    final result =
        await conversations.removeMember(conversation.id, targetUserId);
    final updated = result.conversation.copyWith(epoch: result.epoch);
    _cacheConversation(updated);
    final me = currentUser!;
    if (updated.isOwner(me.id)) {
      final gmk = await chatCrypto.rotateGroupEpoch(updated.id, result.epoch);
      await groupKeys.publishEpochKeys(updated, gmk);
      await groupKeys.resetRotationMeta(updated.id);
    }
    return updated;
  }

  ChatMessage _asSystemMessage(ChatMessage msg) {
    return msg.copyWith(plaintext: msg.ciphertext);
  }

  Future<void> leaveGroup(ConversationItem conversation) async {
    final me = currentUser!;
    var messages = await loadCachedMessages(conversation.id);
    final result = await conversations.removeMember(conversation.id, me.id);
    final sys = result.systemMessage;
    if (sys != null && !messages.any((m) => m.id == sys.id)) {
      messages = [...messages, _asSystemMessage(sys)];
    }
    await archiveConversation(
      conversation,
      messages: messages.isEmpty ? null : messages,
    );
  }

  Future<void> dissolveGroup(ConversationItem conversation) async {
    await conversations.dissolveGroup(conversation.id);
    await archiveConversation(conversation.copyWith(isArchived: true));
  }

  /// 退群/被踢后保留本地会话与消息，仅标记为只读归档。
  Future<void> archiveConversation(
    ConversationItem conversation, {
    List<ChatMessage>? messages,
  }) async {
    final me = currentUser;
    if (me == null) return;

    final archived = conversation.copyWith(isArchived: true);
    await storage.saveArchivedConversation(me.id, archived.toJson());
    _cacheConversation(archived);
    await setConversationPinned(conversation.id, pinned: false);

    if (messages != null && messages.isNotEmpty) {
      await cacheMessages(conversation.id, messages);
    }
  }

  /// 重新加入群聊时取消归档，恢复为活跃会话。
  Future<ConversationItem> reactivateConversation(ConversationItem conv) async {
    final me = currentUser;
    if (me == null) return conv;
    await storage.removeArchivedConversation(me.id, conv.id);
    final active = conv.copyWith(isArchived: false);
    _cacheConversation(active);
    return active;
  }

  /// 合并 WS/API 推送的会话元数据，避免空 members 覆盖本地完整数据。
  ConversationItem mergeConversationUpdate(
    ConversationItem existing,
    ConversationItem incoming,
  ) {
    final merged = existing.copyWith(
      name: incoming.name ?? existing.name,
      avatarUrl: incoming.avatarUrl?.isNotEmpty == true
          ? incoming.avatarUrl
          : existing.avatarUrl,
      epoch: incoming.epoch,
      members: incoming.members.isNotEmpty ? incoming.members : existing.members,
      lastMessage: incoming.lastMessage ?? existing.lastMessage,
      isArchived: false,
    );
    _cacheConversation(merged);
    if (merged.type == 'group') {
      unawaited(ensureGroupMemberDirectory(merged));
    }
    return merged;
  }

  /// 若会话已重新出现在服务端列表中，则取消归档。
  Future<ConversationItem?> tryReactivateConversation(
    ConversationItem conversation,
  ) async {
    if (!conversation.isArchived) return conversation;
    try {
      final items = await conversations.listConversations();
      for (final c in items) {
        if (c.id == conversation.id) {
          return reactivateConversation(c);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<ConversationItem>> listAllConversations() async {
    final me = currentUser!;
    final active = await conversations.listConversations();
    final activeIds = active.map((c) => c.id).toSet();
    await storage.removeArchivedConversations(me.id, activeIds);
    for (final c in active) {
      _cacheConversation(c.copyWith(isArchived: false));
    }

    final archivedRaw = await storage.readArchivedConversationsRaw(me.id);
    final merged = List<ConversationItem>.from(active);
    for (final raw in archivedRaw) {
      final item = ConversationItem.fromJson(raw);
      if (!activeIds.contains(item.id)) {
        merged.add(item);
        _cacheConversation(item);
      }
    }
    await persistConversationList(merged);
    return merged;
  }

  Future<void> persistConversationList(List<ConversationItem> items) async {
    final me = currentUser;
    if (me == null) return;
    for (final c in items) {
      _cacheConversation(c);
    }
    await storage.saveConversationListSnapshot(
      me.id,
      items.map((c) => c.toJson()).toList(),
    );
  }

  /// 离线或刷新失败时读取上次成功的会话列表快照。
  Future<List<ConversationItem>> listCachedConversations() async {
    final me = currentUser;
    if (me == null) return [];
    if (_conversationCache.isNotEmpty) {
      return _conversationCache.values.toList();
    }
    final raw = await storage.readConversationListSnapshot(me.id);
    final items = raw.map((e) => ConversationItem.fromJson(e)).toList();
    for (final c in items) {
      _cacheConversation(c);
    }
    return items;
  }

  Future<String?> cachedPlaintextForMessage(
    String conversationId,
    String messageId,
  ) async {
    final mem = _messagesMem[conversationId];
    if (mem != null) {
      for (final m in mem) {
        if (m.id != messageId) continue;
        final pt = m.plaintext;
        if (_isValidCachedPlaintext(pt)) return pt;
        break;
      }
    }
    final cached = await loadCachedMessages(conversationId);
    for (final m in cached) {
      if (m.id != messageId) continue;
      final pt = m.plaintext;
      if (_isValidCachedPlaintext(pt)) return pt;
    }
    return null;
  }

  bool _isValidCachedPlaintext(String? pt) {
    if (pt == null || pt.isEmpty) return false;
    if (ChatMessage.isDecryptPlaceholder(pt)) return false;
    if (ChatMessage.isDecryptFailure(pt)) return false;
    return true;
  }

  Future<void> upsertCachedMessage(
    String conversationId,
    ChatMessage message,
  ) async {
    if (!_isValidCachedPlaintext(message.plaintext)) return;
    final list = List<ChatMessage>.from(
      _messagesMem[conversationId] ?? await loadCachedMessages(conversationId),
    );
    final i = list.indexWhere((m) => m.id == message.id);
    if (i >= 0) {
      list[i] = message;
    } else {
      list.add(message);
    }
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messagesMem[conversationId] = list;
    await cacheMessages(conversationId, list);
  }

  Future<void> cacheMessages(
    String conversationId,
    List<ChatMessage> messages,
  ) async {
    final me = currentUser;
    if (me == null || messages.isEmpty) return;
    final stored = <ChatMessage>[];
    for (final m in messages) {
      stored.add(await _compactMessageForCache(m));
    }
    _messagesMem[conversationId] = stored;
    await storage.saveMessageCache(
      me.id,
      conversationId,
      stored.map((m) => m.toJson()).toList(),
    );
  }

  Future<ChatMessage> _compactMessageForCache(ChatMessage msg) async {
    final pt = msg.plaintext;
    if (pt == null || pt.isEmpty) return msg;
    if (ChatMessage.isDecryptPlaceholder(pt)) return msg.forCacheWithoutPlaintext;
    if (ChatMessage.isDecryptFailure(pt)) return msg.forCacheWithoutPlaintext;
    if (msg.type == 'image' || msg.type == 'audio') {
      if (MediaLocalCache.isLocalRef(pt)) return msg;
      final compact = await MediaLocalCache.persistPlaintext(msg.id, pt);
      if (compact != null) return msg.copyWith(plaintext: compact);
      return msg.forCacheWithoutPlaintext;
    }
    if (msg.type == 'file') {
      if (MediaLocalCache.isLocalRef(pt)) return msg;
      if (await MediaLocalCache.hasPayloadFile(msg.id)) {
        final ref = await MediaLocalCache.localRefFromDisk(msg.id);
        if (ref != null) return msg.copyWith(plaintext: ref);
      }
      return msg.forCacheWithoutPlaintext;
    }
    if (_isMediaPlaintext(msg.type, pt)) return msg.forCacheWithoutPlaintext;
    return msg;
  }

  /// 本地缓存是否已含可展示内容（媒体须已落盘或仍带 inline 数据）。
  Future<bool> cachedMessagesFullyAvailable(List<ChatMessage> messages) async {
    if (messages.isEmpty) return false;
    for (final m in messages) {
      if (m.type == 'system') continue;
      if (m.type == 'file') continue;
      final pt = m.plaintext;
      if (pt == null || pt.isEmpty) return false;
      if (ChatMessage.isDecryptPlaceholder(pt)) return false;
      if (_isMediaPlaintext(m.type, pt) &&
          !await MediaLocalCache.isPlaintextAvailable(m.id, pt)) {
        return false;
      }
    }
    return true;
  }

  Future<List<ChatMessage>> loadCachedMessages(String conversationId) async {
    final mem = _messagesMem[conversationId];
    if (mem != null) return List<ChatMessage>.from(mem);
    final me = currentUser;
    if (me == null) return [];
    final raw = await storage.readMessageCache(me.id, conversationId);
    final list = raw.map((e) => ChatMessage.fromJson(e)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messagesMem[conversationId] = list;
    return list;
  }

  /// 批量读取本地消息缓存，供首页跨 epoch 搜索历史。
  Future<Map<String, List<ChatMessage>>> loadCachedMessagesForConversations(
    Iterable<String> conversationIds,
  ) async {
    final entries = await Future.wait(
      conversationIds.map(
        (id) async => MapEntry(id, await loadCachedMessages(id)),
      ),
    );
    return {
      for (final e in entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
  }

  /// 读取本机持久化消息并尽力解密，供搜索使用（不拉取消息列表 API）。
  Future<List<ChatMessage>> loadLocalMessagesForSearch(
    ConversationItem conversation,
  ) async {
    final messages = await loadCachedMessages(conversation.id);
    if (messages.isEmpty) return messages;
    final conv = _conversationCache[conversation.id] ?? conversation;
    if (conv.type == 'group') {
      try {
        await ensureGroupKeysForMessages(conv, messages);
      } catch (_) {}
    }
    return decryptMessagesLocal(conv, messages);
  }

  Future<Map<String, List<ChatMessage>>> loadLocalMessagesForConversations(
    Iterable<ConversationItem> conversations,
  ) async {
    final out = <String, List<ChatMessage>>{};
    for (final conv in conversations) {
      final msgs = await loadLocalMessagesForSearch(conv);
      if (msgs.isNotEmpty) out[conv.id] = msgs;
    }
    return out;
  }

  /// 媒体 plaintext 已损坏（local 引用但文件缺失等）时需重新解密。
  Future<bool> messagePlaintextNeedsRepair(ChatMessage msg) async {
    if (msg.type == 'system') return false;
    if (msg.type == 'file') {
      return !await MediaLocalCache.hasPayloadFile(msg.id);
    }
    final pt = msg.plaintext;
    if (pt == null || pt.isEmpty) return true;
    if (ChatMessage.isDecryptPlaceholder(pt)) return true;
    if (ChatMessage.isDecryptFailure(pt)) return true;
    if (!_isMediaPlaintext(msg.type, pt)) return false;
    return !await MediaLocalCache.isPlaintextAvailable(msg.id, pt);
  }

  bool _isMediaPlaintext(String type, String? pt) =>
      type == 'image' ||
      type == 'audio' ||
      type == 'file' ||
      MediaLocalCache.isLocalRef(pt) ||
      MediaPayload.tryParse(pt) != null;

  Future<ChatMessage> _finalizeDecryptedMedia(
    String conversationId,
    ChatMessage dec, {
    bool persistFile = false,
  }) async {
    final pt = dec.plaintext;
    if (pt == null || pt.isEmpty) return dec;
    if (ChatMessage.isDecryptPlaceholder(pt)) return dec;
    if (ChatMessage.isDecryptFailure(pt)) return dec;
    if (dec.type == 'image' ||
        dec.type == 'audio' ||
        (dec.type == 'file' && persistFile)) {
      final compact = await MediaLocalCache.persistPlaintext(dec.id, pt);
      if (compact != null) {
        final cached = dec.copyWith(plaintext: compact);
        unawaited(upsertCachedMessage(conversationId, cached));
        return cached;
      }
    } else if (dec.type == 'text') {
      unawaited(upsertCachedMessage(conversationId, dec));
    }
    return dec;
  }

  Future<ChatMessage> _decryptOneLocal(
    ConversationItem conversation,
    ChatMessage msg, {
    bool persistFile = false,
  }) async {
    final conv = _conversationCache[conversation.id] ?? conversation;
    var base = msg;
    if (base.ciphertext.isEmpty) {
      base = await hydrateIncomingMessage(conversation.id, msg);
    }
    final me = currentUser;
    if (me != null && base.senderId == me.id && conv.type != 'group') {
      final inline = base.plaintext;
      if (inline != null &&
          inline.isNotEmpty &&
          !ChatMessage.isDecryptPlaceholder(inline) &&
          !ChatMessage.isDecryptFailure(inline)) {
        if (base.type == 'image' || base.type == 'audio') {
          return _finalizeDecryptedMedia(conversation.id, base);
        }
        return base;
      }
      final stored = await _resolvePlaintext(conversation.id, base.id);
      if (stored != null) {
        return base.copyWith(plaintext: stored);
      }
      return base.copyWith(plaintext: ChatMessage.decryptPlaceholder);
    }
    final cached = await _resolvePlaintext(conversation.id, base.id);
    if (cached != null) {
      final withPt = base.copyWith(plaintext: cached);
      if ((base.type == 'image' || base.type == 'audio') &&
          MediaPayload.tryParse(cached) != null) {
        return _finalizeDecryptedMedia(conversation.id, withPt);
      }
      return withPt;
    }
    if (conv.type == 'group') {
      try {
        await ensureGroupKeys(conv, epochs: [base.epoch], waitForRelay: true);
      } catch (_) {}
    }
    final dec = await chatCrypto.decryptMessage(conv, base);
    if (dec.type == 'file') {
      if (persistFile) {
        return _finalizeDecryptedMedia(
          conversation.id,
          dec,
          persistFile: true,
        );
      }
      if (await MediaLocalCache.hasPayloadFile(dec.id)) {
        final ref = MediaLocalCache.isLocalRef(dec.plaintext)
            ? dec.plaintext
            : await MediaLocalCache.localRefFromDisk(dec.id);
        if (ref != null) return dec.copyWith(plaintext: ref);
      }
      return dec.copyWith(plaintext: ChatMessage.decryptPlaceholder);
    }
    return _finalizeDecryptedMedia(conversation.id, dec);
  }

  Future<String?> _resolvePlaintext(
    String conversationId,
    String messageId, {
    List<ChatMessage>? thread,
  }) async {
    if (thread != null) {
      for (final m in thread) {
        if (m.id != messageId) continue;
        final pt = m.plaintext;
        if (pt == null || pt.isEmpty) break;
        if (ChatMessage.isDecryptPlaceholder(pt)) break;
        if (ChatMessage.isDecryptFailure(pt)) break;
        return pt;
      }
    }
    return cachedPlaintextForMessage(conversationId, messageId);
  }

  /// 单条消息媒体修复（文件：用户点击接收；其它：缓存 local 引用失效时重新解密）。
  Future<ChatMessage?> repairMessageMedia(
    ConversationItem conversation,
    ChatMessage message,
  ) async {
    if (message.type == 'system') return message;
    if (message.type == 'file') {
      if (await MediaLocalCache.hasPayloadFile(message.id)) {
        final ref = MediaLocalCache.isLocalRef(message.plaintext)
            ? message.plaintext
            : await MediaLocalCache.localRefFromDisk(message.id);
        if (ref != null) {
          final fixed = message.copyWith(plaintext: ref);
          unawaited(upsertCachedMessage(conversation.id, fixed));
          return fixed;
        }
      }
      if (conversation.type == 'group') {
        try {
          await ensureGroupKeysForMessages(conversation, [message]);
        } catch (_) {}
      }
      try {
        return await _decryptOneLocal(
          conversation,
          message,
          persistFile: true,
        );
      } catch (_) {
        return null;
      }
    }
    if (!await messagePlaintextNeedsRepair(message)) return message;
    if (conversation.type == 'group') {
      try {
        await ensureGroupKeysForMessages(conversation, [message]);
      } catch (_) {}
    }
    try {
      return await _finalizeDecryptedMedia(conversation.id,
          await _decryptOneLocal(conversation, message));
    } catch (_) {
      return null;
    }
  }

  /// 仅使用本机会话与密钥解密，不刷新服务端会话元数据。
  Future<List<ChatMessage>> decryptMessagesLocal(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) async {
    final out = <ChatMessage>[];
    for (final msg in messages) {
      if (ChatMessage.isLocalId(msg.id)) {
        out.add(msg);
        continue;
      }
      if (msg.type == 'system') {
        out.add(msg.copyWith(plaintext: msg.ciphertext));
        continue;
      }
      if (msg.type == 'file') {
        if (await MediaLocalCache.hasPayloadFile(msg.id)) {
          var ref = msg.plaintext;
          if (!MediaLocalCache.isLocalRef(ref)) {
            ref = await MediaLocalCache.localRefFromDisk(msg.id);
          }
          out.add(ref != null ? msg.copyWith(plaintext: ref) : msg);
        } else {
          out.add(msg.copyWith(plaintext: ChatMessage.decryptPlaceholder));
        }
        continue;
      }
      if (msg.plaintext != null &&
          msg.plaintext!.isNotEmpty &&
          !await messagePlaintextNeedsRepair(msg)) {
        out.add(msg);
        continue;
      }
      try {
        out.add(await _decryptOneLocal(conversation, msg));
      } catch (_) {
        out.add(msg);
      }
    }
    return out;
  }

  /// 群聊解散后归档本地记录（仍可在本地查看历史）。
  Future<void> handleGroupDissolved(String conversationId) async {
    final conv = _conversationCache[conversationId];
    if (conv != null) {
      await archiveConversation(conv);
    }
  }

  /// 同一退群事件只展示一次 UI（会话列表与聊天页都会收到 WS）。
  bool claimRemovalUi(String conversationId) {
    final now = DateTime.now();
    final prev = _removalUiClaimed[conversationId];
    if (prev != null && now.difference(prev) < const Duration(seconds: 5)) {
      return false;
    }
    _removalUiClaimed[conversationId] = now;
    return true;
  }

  /// 被移出群聊后归档，不从本地列表移除。
  Future<void> handleConversationRemoved(
    String conversationId, {
    ConversationItem? snapshot,
    List<ChatMessage>? messages,
  }) async {
    final conv = snapshot ?? _conversationCache[conversationId];
    if (conv != null) {
      await archiveConversation(conv, messages: messages);
      return;
    }
    await archiveConversation(
      ConversationItem(
        id: conversationId,
        type: 'group',
        members: const [],
        isArchived: true,
      ),
      messages: messages,
    );
  }

  Future<void> ensureGroupKeys(
    ConversationItem conversation, {
    List<int>? epochs,
    bool waitForRelay = false,
  }) =>
      groupKeys.ensureKeys(
        conversation,
        epochs: epochs,
        waitForRelay: waitForRelay,
      );

  Future<void> ensureOwnerGroupKeys(ConversationItem conversation) =>
      groupKeys.ensureOwnerKeys(conversation);

  Future<void> ensureGroupKeysForMessages(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) =>
      groupKeys.prepareForMessages(conversation, messages);

  void prepareGroupConversation(ConversationItem conversation) =>
      groupKeys.prepareForConversation(conversation);

  Future<ConversationItem> _refreshConversation(ConversationItem conversation) async {
    if (conversation.isArchived) {
      final reactivated = await tryReactivateConversation(conversation);
      if (reactivated != null) {
        conversation = reactivated;
      } else {
        return _conversationCache[conversation.id] ?? conversation;
      }
    }
    try {
      final items = await conversations.listConversations();
      final me = currentUser;
      for (final c in items) {
        if (c.id == conversation.id && me != null) {
          await storage.removeArchivedConversation(me.id, c.id);
        }
        _cacheConversation(
          c.id == conversation.id ? c.copyWith(isArchived: false) : c,
        );
      }
      return items.firstWhere(
        (c) => c.id == conversation.id,
        orElse: () =>
            _conversationCache[conversation.id]?.copyWith(isArchived: false) ??
            conversation,
      );
    } catch (_) {
      return _conversationCache[conversation.id] ?? conversation;
    }
  }

  Future<ChatMessage> decryptMessage(
    ConversationItem conversation,
    ChatMessage message,
  ) async {
    return _decryptOneLocal(conversation, message);
  }

  Future<List<ChatMessage>> decryptMessages(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) async {
    return decryptMessagesLocal(conversation, messages);
  }

  Future<ConversationItem> refreshConversation(ConversationItem conversation) {
    return _refreshConversation(conversation);
  }

  Future<String> decryptPreview(
    ConversationItem conversation,
    ChatMessage message, {
    List<ChatMessage>? cachedThread,
  }) async {
    final hydrated =
        await hydrateIncomingMessage(conversation.id, message);
    if (hydrated.type == 'system') {
      return hydrated.ciphertext;
    }
    final conv = _conversationCache[conversation.id] ?? conversation;
    final me = currentUser;
    if (me != null && hydrated.senderId == me.id && conv.type != 'group') {
      final stored = await _resolvePlaintext(
        conversation.id,
        hydrated.id,
        thread: cachedThread,
      );
      if (stored != null) return _previewBody(hydrated, stored);
      return hydrated.type == 'text'
          ? ChatMessage.decryptPlaceholder
          : MediaPayload.previewLabel('', hydrated.type);
    }
    final stored = await _resolvePlaintext(
      conversation.id,
      hydrated.id,
      thread: cachedThread,
    );
    if (stored != null) return _previewBody(hydrated, stored);
    if (conv.type == 'group') {
      unawaited(ensureGroupKeys(conv, epochs: [hydrated.epoch]));
    }
    final text = await chatCrypto.decryptIncoming(
      conv,
      hydrated.ciphertext,
      messageEpoch: hydrated.epoch,
    );
    if (ChatMessage.isDecryptFailure(text)) {
      final retry = await _resolvePlaintext(
        conversation.id,
        hydrated.id,
        thread: cachedThread,
      );
      if (retry != null) return _previewBody(hydrated, retry);
      return text;
    }
    final preview = _previewBody(hydrated, text);
    unawaited(
      upsertCachedMessage(
        conversation.id,
        hydrated.copyWith(plaintext: preview),
      ),
    );
    return preview;
  }

  String _previewBody(ChatMessage message, String plaintext) {
    if (message.type == 'text') return plaintext;
    return MediaPayload.previewLabel(plaintext, message.type);
  }

  /// WS 推送大消息时 ciphertext 可能被省略；优先读本机缓存，再请求 API。
  Future<ChatMessage> hydrateIncomingMessage(
    String conversationId,
    ChatMessage message,
  ) async {
    if (message.ciphertext.isNotEmpty) return message;
    final cached = await loadCachedMessages(conversationId);
    for (final m in cached) {
      if (m.id == message.id) return m;
    }
    try {
      final msgs =
          await conversations.listMessages(conversationId, limit: 30);
      for (final m in msgs) {
        if (m.id == message.id) return m;
      }
    } catch (_) {}
    return message;
  }

  Future<void> reconnectRealtime() async {
    final token = await ensureValidAccessToken();
    if (token == null || token.isEmpty) return;
    await ws.reconnect(token);
  }

  /// 登录/进首页时确保 WS 已连上；失败则指数退避重试。
  Future<void> ensureRealtimeConnected({int maxAttempts = 4}) async {
    if (ws.isConnected) return;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await reconnectRealtime();
      for (var i = 0; i < 6; i++) {
        if (ws.isConnected) return;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (attempt + 1 < maxAttempts) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
  }

  void _cacheConversation(ConversationItem conv) {
    _conversationCache[conv.id] = conv;
    if (conv.type == 'group' && conv.members.isNotEmpty) {
      unawaited(mergeMemberDirectory(conv.id, conv.members));
    }
  }

  Future<Map<String, ConversationMember>> _directoryFor(
    String conversationId,
  ) async {
    final cached = _memberDirectories[conversationId];
    if (cached != null) return cached;
    final me = currentUser;
    if (me == null) return {};
    return _directoryFromStorage(me.id, conversationId);
  }

  Future<void> mergeMemberDirectory(
    String conversationId,
    List<ConversationMember> members, {
    bool persist = true,
  }) async {
    final me = currentUser;
    if (me == null || members.isEmpty) return;
    final dir = _memberDirectories[conversationId] ??
        await _directoryFromStorage(me.id, conversationId);
    var changed = false;
    for (final m in members) {
      if (m.userId.isEmpty) continue;
      final existing = dir[m.userId];
      if (existing == null ||
          existing.username != m.username ||
          existing.avatarUrl != m.avatarUrl ||
          existing.identityPublicKey != m.identityPublicKey) {
        dir[m.userId] = m;
        changed = true;
      }
    }
    if (!changed) return;
    _memberDirectories[conversationId] = dir;
    if (persist) {
      await storage.saveMemberDirectory(
        me.id,
        conversationId,
        dir.values.map((m) => m.toJson()).toList(),
      );
    }
  }

  Future<Map<String, ConversationMember>> _directoryFromStorage(
    String userId,
    String conversationId,
  ) async {
    final raw = await storage.readMemberDirectory(userId, conversationId);
    final map = <String, ConversationMember>{};
    for (final e in raw) {
      final m = ConversationMember.fromJson(e);
      if (m.userId.isNotEmpty) map[m.userId] = m;
    }
    _memberDirectories[conversationId] = map;
    return map;
  }

  /// 拉取并合并群成员名录（含已退群），供历史消息展示昵称/头像。
  Future<void> ensureGroupMemberDirectory(ConversationItem conversation) async {
    if (conversation.type != 'group') return;
    await mergeMemberDirectory(conversation.id, conversation.members);
    if (_memberDirectorySynced.contains(conversation.id)) return;
    try {
      final remote =
          await conversations.listMemberDirectory(conversation.id);
      await mergeMemberDirectory(conversation.id, remote);
      _memberDirectorySynced.add(conversation.id);
    } catch (_) {}
  }

  ConversationMember? knownGroupMember(
    ConversationItem conversation,
    String userId,
  ) {
    for (final m in conversation.members) {
      if (m.userId == userId) return m;
    }
    return _memberDirectories[conversation.id]?[userId];
  }

  Future<ConversationMember?> groupMemberProfile(
    ConversationItem conversation,
    String userId,
  ) async {
    final active = knownGroupMember(conversation, userId);
    if (active != null) return active;
    final dir = await _directoryFor(conversation.id);
    return dir[userId];
  }

  String groupSenderLabel(
    ConversationItem conversation,
    String meId,
    String senderId,
  ) {
    if (senderId == meId) return '我';
    return groupMemberUsername(conversation, senderId);
  }

  String groupMemberUsername(ConversationItem conversation, String userId) {
    final profile = knownGroupMember(conversation, userId);
    return profile?.username ?? '?';
  }

  String? groupMemberAvatarUrl(ConversationItem conversation, String userId) {
    return knownGroupMember(conversation, userId)?.avatarUrl;
  }

  Future<void> _connectRealtime() async {
    final token = await ensureValidAccessToken();
    if (token == null || token.isEmpty) return;
    await ws.connect(token);
    groupKeys.attachWsHandlers();
    try {
      final items = await conversations.listConversations();
      for (final c in items) {
        _cacheConversation(c);
      }
      groupKeys.syncAllCachedInBackground(_conversationCache.values);
    } catch (_) {}
  }

  Future<void> _disconnectRealtime() async {
    groupKeys.detachWsHandlers();
    await ws.disconnect();
  }

  /// 登录后上传 Signal 预密钥并同步身份公钥。
  Future<bool> _ensureSignalIdentity() async {
    final user = currentUser;
    if (user == null) return false;

    await storage.bindSignalStoreForUser(
      userId: user.id,
      email: user.email,
    );
    _signalDm = null;
    _crypto = null;

    final dm = await _ensureSignalDm();
    await dm.uploadKeysToServer();
    final localPub = await dm.identityPublicKeyBase64();

    if (!isValidIdentityPublicKey(user.identityPublicKey) ||
        user.identityPublicKey != localPub) {
      final data = await api.patchJson('/api/users/me', body: {
        'identity_public_key': localPub,
      });
      currentUser = User.fromJson(data);
      return true;
    }
    return false;
  }
}
