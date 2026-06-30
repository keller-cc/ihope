import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../crypto/chat_crypto.dart';
import '../crypto/e2ee_exception.dart';
import '../crypto/identity.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../utils/media_local_cache.dart';
import '../utils/media_payload.dart';
import 'api_client.dart';
import 'auth_storage.dart';
import 'conversation_service.dart';
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
  StreamSubscription<KeyRelayFrame>? _keyRelaySub;
  StreamSubscription<GmkRequestFrame>? _gmkRequestSub;
  StreamSubscription<EpochUpdatedFrame>? _epochSub;
  final Map<String, ConversationItem> _conversationCache = {};
  String? _openConversationId;
  final Map<String, int> _unreadCounts = {};
  final Map<String, List<Completer<void>>> _gmkWaiters = {};
  final Map<String, DateTime> _removalUiClaimed = {};

  DateTime? _accessExpiresAt;
  Future<bool>? _refreshInFlight;

  static const _refreshSkew = Duration(minutes: 2);

  ChatCrypto get chatCrypto {
    final user = currentUser;
    if (user == null) {
      throw StateError('not logged in');
    }
    return _crypto ??= _createChatCrypto(user);
  }

  ChatCrypto _createChatCrypto(User user) {
    return createChatCrypto(
      myUserId: user.id,
      readIdentitySeed: () => storage.readIdentitySeedForUser(user.id),
      writeIdentitySeed: (seed) => storage.writeIdentitySeedForUser(user.id, seed),
      readSession: (peer) => storage.readSessionKey(user.id, peer),
      readSessionPeerKey: (peer) => storage.readSessionPeerKey(user.id, peer),
      writeSession: (peer, bytes, peerPub) => storage.writeSessionKey(
        user.id,
        peer,
        bytes,
        peerPublicKey: peerPub,
      ),
      clearSession: (peer) => storage.clearSessionKey(user.id, peer),
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
        _accessExpiresAt = null;
        return false;
      }
      await refreshCurrentUser();
    }
    try {
      await _bindIdentityForUser();
      await _connectRealtime();
      return true;
    } catch (_) {
      await _disconnectRealtime();
      await storage.clear();
      api.setAccessToken(null);
      _crypto = null;
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
    await _applyTokenResponse(data);
    await _bindIdentityForUser();
    return currentUser!;
  }

  Future<User> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final pubKey = await identityPublicKeyForRegister(
      readIdentitySeed: () =>
          storage.readIdentitySeedForEmail(normalizedEmail),
      writeIdentitySeed: (seed) =>
          storage.writeIdentitySeedForEmail(normalizedEmail, seed),
    );
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
    _conversationCache.clear();
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
      await markConversationRead(msg.conversationId, upTo: msg.createdAt);
      return;
    }
    final me = currentUser;
    if (me == null || msg.senderId == me.id) return;
    _unreadCounts[msg.conversationId] =
        (_unreadCounts[msg.conversationId] ?? 0) + 1;
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
    final fresh = await _refreshConversation(conversation);
    if (fresh.type == 'group') {
      await ensureGroupKeys(fresh, epochs: [fresh.epoch]);
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
    return msg.copyWith(plaintext: plaintext);
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
    await _relayGroupWelcome(conv, gmk);
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
    await _relayGroupWelcome(updated, gmk);
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
      await _relayGroupWelcome(updated, gmk);
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
    for (final c in active) {
      await storage.removeArchivedConversation(me.id, c.id);
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
    if (!_isMediaPlaintext(msg.type, pt)) return msg;
    final compact = await MediaLocalCache.persistPlaintext(msg.id, pt);
    if (compact == null) return msg;
    if (!await MediaLocalCache.hasPayloadFile(msg.id)) return msg;
    return msg.copyWith(plaintext: compact);
  }

  /// 本地缓存是否已含可展示内容（媒体须已落盘或仍带 inline 数据）。
  Future<bool> cachedMessagesFullyAvailable(List<ChatMessage> messages) async {
    if (messages.isEmpty) return false;
    for (final m in messages) {
      if (m.type == 'system') continue;
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
    final me = currentUser;
    if (me == null) return [];
    final raw = await storage.readMessageCache(me.id, conversationId);
    return raw.map((e) => ChatMessage.fromJson(e)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
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
    final pt = msg.plaintext;
    if (pt == null || pt.isEmpty) return true;
    if (ChatMessage.isDecryptPlaceholder(pt)) return true;
    if (!_isMediaPlaintext(msg.type, pt)) return false;
    return !await MediaLocalCache.isPlaintextAvailable(msg.id, pt);
  }

  bool _isMediaPlaintext(String type, String? pt) =>
      type == 'image' ||
      type == 'audio' ||
      type == 'file' ||
      MediaLocalCache.isLocalRef(pt) ||
      MediaPayload.tryParse(pt) != null;

  Future<ChatMessage> _decryptOneLocal(
    ConversationItem conversation,
    ChatMessage msg,
  ) async {
    final conv = _conversationCache[conversation.id] ?? conversation;
    var base = msg;
    if (base.ciphertext.isEmpty) {
      base = await hydrateIncomingMessage(conversation.id, msg);
    }
    final dec = await chatCrypto.decryptMessage(conv, base);
    final pt = dec.plaintext;
    if (pt != null && pt.isNotEmpty) {
      await MediaLocalCache.resolve(dec.id, pt);
    }
    return dec;
  }

  /// 单条消息媒体修复（缓存 local 引用失效时重新解密并落盘）。
  Future<ChatMessage?> repairMessageMedia(
    ConversationItem conversation,
    ChatMessage message,
  ) async {
    if (message.type == 'system') return message;
    if (!await messagePlaintextNeedsRepair(message)) return message;
    if (conversation.type == 'group') {
      try {
        await ensureGroupKeysForMessages(conversation, [message]);
      } catch (_) {}
    }
    try {
      return await _decryptOneLocal(conversation, message);
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
      if (msg.type == 'system') {
        out.add(msg.copyWith(plaintext: msg.ciphertext));
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

  /// 确保本地有所需 epoch 的群 GMK（优先 REST 拉取服务端密文包，其次 WS 向在线群主补发）。
  Future<void> ensureGroupKeys(
    ConversationItem conversation, {
    List<int>? epochs,
  }) async {
    if (conversation.type != 'group') return;
    final me = currentUser;
    if (me == null) return;

    var conv = conversation;
    if (conv.members.isEmpty) {
      conv = await _refreshConversation(conversation);
    }

    final needed = <int>{conv.epoch, ...?epochs};
    for (final epoch in needed) {
      if (await _hasGroupGmk(conv.id, epoch)) continue;

      if (conv.isOwner(me.id)) {
        if (await _fetchOwnerSelfBundle(conv, epoch)) continue;
        await _backfillKeyBundlesForOwner(conv, epochs: {epoch});
        continue;
      }

      final fromServer = await _fetchKeyBundlesFromServer(conv, epoch);
      if (fromServer || await _hasGroupGmk(conv.id, epoch)) continue;

      await _requestGmkAndWait(conv.id, epoch);
    }
  }

  /// 群主换设备后，从服务端自备份拉取历史 epoch 的 GMK。
  Future<void> ensureOwnerGroupKeys(ConversationItem conversation) async {
    if (conversation.type != 'group') return;
    final me = currentUser;
    if (me == null || !conversation.isOwner(me.id)) return;

    var conv = conversation;
    if (conv.members.isEmpty) {
      conv = await _refreshConversation(conversation);
    }

    try {
      final bundles = await conversations.fetchKeyBundles(conv.id);
      final epochs = <int>{conv.epoch};
      for (final b in bundles) {
        epochs.add(b.epoch);
      }
      for (var e = 0; e <= conv.epoch; e++) {
        epochs.add(e);
      }
      await ensureGroupKeys(conv, epochs: epochs.toList());
    } catch (_) {
      await ensureGroupKeys(conv);
    }
  }

  Future<void> ensureGroupKeysForMessages(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) async {
    if (conversation.type != 'group') return;
    final epochs = messages.map((m) => m.epoch).toSet().toList();
    await ensureGroupKeys(conversation, epochs: epochs);
  }

  Future<bool> _hasGroupGmk(String conversationId, int epoch) async {
    final me = currentUser;
    if (me == null) return false;
    final raw = await storage.readGroupGmk(me.id, conversationId, epoch);
    return raw != null && raw.length == 32;
  }

  Future<bool> _fetchOwnerSelfBundle(
    ConversationItem conv,
    int epoch,
  ) async {
    final me = currentUser;
    if (me == null || !conv.isOwner(me.id)) return false;

    ConversationMember? owner;
    for (final m in conv.members) {
      if (m.userId == me.id) {
        owner = m;
        break;
      }
    }
    if (owner == null || !canUseE2EEWithPeer(owner.identityPublicKey)) {
      return false;
    }

    try {
      final bundles = await conversations.fetchKeyBundles(
        conv.id,
        epochs: [epoch],
      );
      for (final bundle in bundles) {
        if (bundle.epoch != epoch || bundle.senderId != me.id) continue;
        if (await _hasGroupGmk(conv.id, epoch)) return true;
        try {
          final stored = await chatCrypto.absorbGroupWelcome(
            senderUserId: me.id,
            senderPublicKeyBase64: owner.identityPublicKey,
            ciphertext: bundle.ciphertext,
          );
          _signalGmkReceived(stored.conversationId, stored.epoch);
        } catch (_) {}
      }
    } catch (_) {}
    return await _hasGroupGmk(conv.id, epoch);
  }

  Future<bool> _fetchKeyBundlesFromServer(
    ConversationItem conv,
    int epoch,
  ) async {
    try {
      final bundles = await conversations.fetchKeyBundles(
        conv.id,
        epochs: [epoch],
      );
      for (final bundle in bundles) {
        if (bundle.epoch != epoch) continue;
        if (await _hasGroupGmk(conv.id, epoch)) return true;

        ConversationMember? sender;
        for (final m in conv.members) {
          if (m.userId == bundle.senderId) {
            sender = m;
            break;
          }
        }
        if (sender == null || !canUseE2EEWithPeer(sender.identityPublicKey)) {
          continue;
        }

        try {
          final stored = await chatCrypto.absorbGroupWelcome(
            senderUserId: sender.userId,
            senderPublicKeyBase64: sender.identityPublicKey,
            ciphertext: bundle.ciphertext,
          );
          _signalGmkReceived(stored.conversationId, stored.epoch);
        } catch (_) {}
      }
    } catch (_) {}
    return await _hasGroupGmk(conv.id, epoch);
  }

  Future<void> _backfillKeyBundlesForOwner(
    ConversationItem conv, {
    required Set<int> epochs,
  }) async {
    final me = currentUser;
    if (me == null || !conv.isOwner(me.id)) return;

    final uploads = <Map<String, dynamic>>[];
    for (final epoch in epochs) {
      final raw = await storage.readGroupGmk(me.id, conv.id, epoch);
      if (raw == null || raw.length != 32) continue;
      final gmk = Uint8List.fromList(raw);

      for (final member in conv.members) {
        if (!canUseE2EEWithPeer(member.identityPublicKey)) continue;
        try {
          final cipher = await chatCrypto.buildGroupWelcome(
            recipient: member,
            conversationId: conv.id,
            epoch: epoch,
            gmk: gmk,
          );
          uploads.add({
            'epoch': epoch,
            'recipient_user_id': member.userId,
            'ciphertext': cipher,
          });
        } catch (_) {}
      }
    }

    if (uploads.isEmpty) return;
    try {
      await conversations.uploadKeyBundles(conv.id, uploads);
    } catch (_) {}
  }

  Future<bool> _requestGmkAndWait(String conversationId, int epoch) async {
    if (await _hasGroupGmk(conversationId, epoch)) return true;

    final key = '$conversationId:$epoch';
    final completer = Completer<void>();
    _gmkWaiters.putIfAbsent(key, () => []).add(completer);
    ws.sendGmkRequest(conversationId: conversationId, epoch: epoch);

    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _gmkWaiters[key]?.remove(completer);
      if (_gmkWaiters[key]?.isEmpty ?? false) {
        _gmkWaiters.remove(key);
      }
      return false;
    }
    return _hasGroupGmk(conversationId, epoch);
  }

  void _signalGmkReceived(String conversationId, int epoch) {
    final key = '$conversationId:$epoch';
    final waiters = _gmkWaiters.remove(key);
    if (waiters == null) return;
    for (final c in waiters) {
      if (!c.isCompleted) c.complete();
    }
  }

  Future<void> _syncGroupKeysInBackground() async {
    final me = currentUser;
    if (me == null) return;
    for (final conv in _conversationCache.values) {
      if (conv.type != 'group') continue;
      if (conv.isOwner(me.id)) {
        unawaited(ensureOwnerGroupKeys(conv));
      } else {
        unawaited(ensureGroupKeys(conv));
      }
    }
  }

  void _cacheConversation(ConversationItem conv) {
    _conversationCache[conv.id] = conv;
  }

  Future<void> _relayGroupWelcome(
    ConversationItem conv,
    Uint8List gmk,
  ) async {
    final me = currentUser;
    if (me == null) return;

    final uploads = <Map<String, dynamic>>[];
    for (final member in conv.members) {
      if (!canUseE2EEWithPeer(member.identityPublicKey)) continue;
      final cipher = await chatCrypto.buildGroupWelcome(
        recipient: member,
        conversationId: conv.id,
        epoch: conv.epoch,
        gmk: gmk,
      );
      if (member.userId != me.id) {
        ws.sendKeyRelay(
          conversationId: conv.id,
          targetUserId: member.userId,
          ciphertext: cipher,
        );
      }
      uploads.add({
        'epoch': conv.epoch,
        'recipient_user_id': member.userId,
        'ciphertext': cipher,
      });
    }

    if (uploads.isNotEmpty) {
      try {
        await conversations.uploadKeyBundles(conv.id, uploads);
      } catch (_) {}
    }
  }

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
    final hydrated =
        await hydrateIncomingMessage(conversation.id, message);
    if (hydrated.type == 'system') {
      return hydrated.copyWith(plaintext: hydrated.ciphertext);
    }
    final conv = await _refreshConversation(conversation);
    return chatCrypto.decryptMessage(conv, hydrated);
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
    ChatMessage message,
  ) async {
    final hydrated =
        await hydrateIncomingMessage(conversation.id, message);
    if (hydrated.type == 'system') {
      return hydrated.ciphertext;
    }
    final conv = await _refreshConversation(conversation);
    if (conv.type == 'group') {
      await ensureGroupKeys(conv, epochs: [hydrated.epoch]);
    }
    return chatCrypto.decryptIncoming(
      conv,
      hydrated.ciphertext,
      messageEpoch: hydrated.epoch,
    );
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

  Future<void> _connectRealtime() async {
    final token = await ensureValidAccessToken();
    if (token == null || token.isEmpty) return;
    await ws.connect(token);
    _attachWsHandlers();
    try {
      final items = await conversations.listConversations();
      for (final c in items) {
        _cacheConversation(c);
      }
      unawaited(_syncGroupKeysInBackground());
    } catch (_) {}
  }

  Future<void> _disconnectRealtime() async {
    await _keyRelaySub?.cancel();
    _keyRelaySub = null;
    await _gmkRequestSub?.cancel();
    _gmkRequestSub = null;
    await _epochSub?.cancel();
    _epochSub = null;
    await ws.disconnect();
  }

  void _attachWsHandlers() {
    _keyRelaySub?.cancel();
    _epochSub?.cancel();
    _keyRelaySub = ws.onKeyRelay.listen((frame) {
      unawaited(_handleKeyRelay(frame));
    });
    _gmkRequestSub = ws.onGmkRequest.listen((frame) {
      unawaited(_handleGmkRequest(frame));
    });
    _epochSub = ws.onEpochUpdated.listen((frame) {
      unawaited(_handleEpochUpdated(frame));
    });
  }

  Future<void> _handleEpochUpdated(EpochUpdatedFrame frame) async {
    final me = currentUser;
    if (me == null) return;

    var conv = _conversationCache[frame.conversationId];
    if (conv != null) {
      conv = conv.copyWith(epoch: frame.epoch);
      _cacheConversation(conv);
    } else {
      conv = ConversationItem(
        id: frame.conversationId,
        type: 'group',
        members: [],
        epoch: frame.epoch,
      );
      _cacheConversation(conv);
    }

    if (!conv.isOwner(me.id)) return;

    final existing =
        await storage.readGroupGmk(me.id, conv.id, frame.epoch);
    if (existing != null) return;

    try {
      final gmk = await chatCrypto.rotateGroupEpoch(conv.id, frame.epoch);
      await _relayGroupWelcome(conv, gmk);
    } catch (_) {}
  }

  Future<void> _handleKeyRelay(KeyRelayFrame frame) async {
    final me = currentUser;
    if (me == null || frame.targetUserId != me.id) return;

    var conv = _conversationCache[frame.conversationId];
    if (conv == null) {
      conv = await _refreshConversation(
        ConversationItem(
          id: frame.conversationId,
          type: 'group',
          members: [],
        ),
      );
    }

    ConversationMember? sender;
    for (final m in conv.members) {
      if (m.userId == frame.fromUserId) {
        sender = m;
        break;
      }
    }
    if (sender == null || !canUseE2EEWithPeer(sender.identityPublicKey)) {
      return;
    }

    try {
      final stored = await chatCrypto.absorbGroupWelcome(
        senderUserId: sender.userId,
        senderPublicKeyBase64: sender.identityPublicKey,
        ciphertext: frame.ciphertext,
      );
      _signalGmkReceived(stored.conversationId, stored.epoch);
    } catch (_) {}
  }

  Future<void> _handleGmkRequest(GmkRequestFrame frame) async {
    final me = currentUser;
    if (me == null) return;

    var conv = _conversationCache[frame.conversationId];
    if (conv == null || conv.members.isEmpty) {
      conv = await _refreshConversation(
        ConversationItem(
          id: frame.conversationId,
          type: 'group',
          members: [],
        ),
      );
    }
    if (!conv.isOwner(me.id)) return;

    ConversationMember? requester;
    for (final m in conv.members) {
      if (m.userId == frame.requesterUserId) {
        requester = m;
        break;
      }
    }
    if (requester == null || !canUseE2EEWithPeer(requester.identityPublicKey)) {
      return;
    }

    for (final epoch in frame.epochs) {
      final raw = await storage.readGroupGmk(me.id, conv.id, epoch);
      if (raw == null || raw.length != 32) continue;
      try {
        final cipher = await chatCrypto.buildGroupWelcome(
          recipient: requester,
          conversationId: conv.id,
          epoch: epoch,
          gmk: Uint8List.fromList(raw),
        );
        ws.sendKeyRelay(
          conversationId: conv.id,
          targetUserId: requester.userId,
          ciphertext: cipher,
        );
        try {
          await conversations.uploadKeyBundles(conv.id, [
            {
              'epoch': epoch,
              'recipient_user_id': requester.userId,
              'ciphertext': cipher,
            },
          ]);
        } catch (_) {}
      } catch (_) {}
    }
  }

  Future<void> _applyTokenResponse(Map<String, dynamic> data) async {
    await _saveTokenResponse(data);
    await _connectRealtime();
  }

  /// 登录后绑定本账号身份密钥（注册 email 密钥 → userId）。
  Future<void> _bindIdentityForUser() async {
    final user = currentUser;
    if (user == null) return;

    await storage.bindIdentityForUser(
      userId: user.id,
      email: user.email,
    );
    _crypto = null;
  }
}
