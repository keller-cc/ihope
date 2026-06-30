import '../models/user.dart';
import 'api_client.dart';
import 'auth_storage.dart';
import 'conversation_service.dart';

class AuthService {
  AuthService({ApiClient? api, AuthStorage? storage})
      : api = api ?? ApiClient(),
        storage = storage ?? AuthStorage();

  final ApiClient api;
  final AuthStorage storage;
  late final ConversationService conversations = ConversationService(api);

  User? currentUser;

  Future<bool> restoreSession() async {
    final token = await storage.accessToken();
    if (token == null || token.isEmpty) {
      return false;
    }
    api.setAccessToken(token);
    try {
      final data = await api.getJson('/api/users/me');
      currentUser = User.fromJson(data);
      return true;
    } catch (_) {
      await storage.clear();
      api.setAccessToken(null);
      return false;
    }
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
    return currentUser!;
  }

  Future<User> register({
    required String email,
    required String username,
    required String password,
  }) async {
    await api.postJson('/api/auth/register', body: {
      'email': email.trim(),
      'username': username.trim(),
      'password': password,
      'identity_public_key': AuthStorage.placeholderIdentityKey(),
    });
    return login(email: email, password: password);
  }

  Future<void> logout() async {
    await storage.clear();
    api.setAccessToken(null);
    currentUser = null;
  }

  Future<String?> accessToken() => storage.accessToken();

  Future<void> _applyTokenResponse(Map<String, dynamic> data) async {
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    await storage.saveTokens(accessToken: access, refreshToken: refresh);
    api.setAccessToken(access);
    currentUser = User.fromJson(data['user'] as Map<String, dynamic>);
  }
}
