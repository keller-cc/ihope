import 'dart:convert';

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

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  /// Phase 2 placeholder; Phase 3 replaces with real identity key pair.
  static String placeholderIdentityKey() {
    return base64Encode(utf8.encode('ihope-phase2-identity-placeholder'));
  }
}
