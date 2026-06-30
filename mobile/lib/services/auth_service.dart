import '../crypto/chat_crypto.dart';
import '../crypto/e2ee_exception.dart';
import '../crypto/identity.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'auth_storage.dart';
import 'conversation_service.dart';
import 'ws_service.dart';

class AuthService {
  AuthService({ApiClient? api, AuthStorage? storage, WsService? ws})
      : api = api ?? ApiClient(),
        storage = storage ?? AuthStorage(),
        ws = ws ?? WsService();

  final ApiClient api;
  final AuthStorage storage;
  final WsService ws;
  late final ConversationService conversations = ConversationService(api);

  User? currentUser;
  ChatCrypto? _crypto;

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
      writeSession: (peer, bytes) =>
          storage.writeSessionKey(user.id, peer, bytes),
    );
  }

  Future<bool> restoreSession() async {
    final token = await storage.accessToken();
    if (token == null || token.isEmpty) {
      return false;
    }
    api.setAccessToken(token);
    try {
      await refreshCurrentUser();
      await _bindIdentityForUser();
      await _connectRealtime();
      return true;
    } catch (_) {
      await _disconnectRealtime();
      await storage.clear();
      api.setAccessToken(null);
      _crypto = null;
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
  }

  Future<String?> accessToken() => storage.accessToken();

  Future<ChatMessage> sendChatMessage(
    ConversationItem conversation,
    String plaintext,
  ) async {
    final me = currentUser;
    if (me == null || !isValidIdentityPublicKey(me.identityPublicKey)) {
      throw E2eeException('本机加密密钥未就绪，请退出后重新登录');
    }
    final fresh = await _refreshConversation(conversation);
    final payload = await chatCrypto.encryptOutgoing(fresh, plaintext);
    if (!payload.startsWith('e2ee:v1:')) {
      throw E2eeException('消息未能加密，已取消发送');
    }
    final msg = await conversations.sendMessage(fresh.id, payload);
    return msg.copyWith(plaintext: plaintext);
  }

  Future<ConversationItem> _refreshConversation(ConversationItem conversation) async {
    try {
      final items = await conversations.listConversations();
      return items.firstWhere(
        (c) => c.id == conversation.id,
        orElse: () => conversation,
      );
    } catch (_) {
      return conversation;
    }
  }

  Future<ChatMessage> decryptMessage(
    ConversationItem conversation,
    ChatMessage message,
  ) {
    return chatCrypto.decryptMessage(conversation, message);
  }

  Future<List<ChatMessage>> decryptMessages(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) {
    return chatCrypto.decryptMessages(conversation, messages);
  }

  Future<String> decryptPreview(
    ConversationItem conversation,
    ChatMessage message,
  ) {
    return chatCrypto.decryptIncoming(conversation, message.ciphertext);
  }

  Future<void> reconnectRealtime() async {
    final token = await storage.accessToken();
    if (token == null || token.isEmpty) return;
    await ws.reconnect(token);
  }

  Future<void> _connectRealtime() async {
    final token = await storage.accessToken();
    if (token == null || token.isEmpty) return;
    await ws.connect(token);
  }

  Future<void> _disconnectRealtime() async {
    await ws.disconnect();
  }

  Future<void> _applyTokenResponse(Map<String, dynamic> data) async {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    await storage.saveTokens(accessToken: access, refreshToken: refresh);
    api.setAccessToken(access);
    currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
    _crypto = null;
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
