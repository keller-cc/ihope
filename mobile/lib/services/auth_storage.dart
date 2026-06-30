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
    return base64Decode(raw);
  }

  Future<void> writeSessionKey(
    String ownerUserId,
    String peerUserId,
    List<int> keyBytes,
  ) async {
    await _storage.write(
      key: _sessionKey(ownerUserId, peerUserId),
      value: base64Encode(keyBytes),
    );
  }

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
