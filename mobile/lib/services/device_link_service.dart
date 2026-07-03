import 'dart:convert';

import '../config/server_config.dart';
import '../services/api_client.dart';
import 'auth_storage.dart';
import 'device_link_crypto.dart';

class DeviceLinkSession {
  DeviceLinkSession({
    required this.linkId,
    required this.token,
    required this.expiresAt,
    required this.qrPayload,
  });

  final String linkId;
  final String token;
  final DateTime expiresAt;
  final String qrPayload;
}

/// 多设备链接：旧设备上传加密密钥包，新设备扫码拉取。
class DeviceLinkService {
  DeviceLinkService({
    required ApiClient api,
    required AuthStorage storage,
    required String Function() currentUserId,
  })  : _api = api,
        _storage = storage,
        _currentUserId = currentUserId;

  final ApiClient _api;
  final AuthStorage _storage;
  final String Function() _currentUserId;

  Future<DeviceLinkSession> startHostSession() async {
    final init = await _api.postJson('/api/device-link/init', body: {});
    final linkId = init['link_id'] as String? ?? '';
    final token = init['token'] as String? ?? '';
    final expiresRaw = init['expires_at'] as String? ?? '';
    if (linkId.isEmpty || token.isEmpty) {
      throw ApiException('无法创建链接会话');
    }

    final userId = _currentUserId();
    final material = await _storage.exportE2eeMaterial(userId);
    if (material.isEmpty) {
      throw ApiException('本机没有可同步的加密密钥，请先完成登录并收发消息后再试');
    }
    final bundle = jsonEncode({'v': 1, 'keys': material});
    final ciphertext = await DeviceLinkCrypto.encrypt(token, bundle);

    await _api.putJson(
      '/api/device-link/$linkId/payload',
      body: {'ciphertext': ciphertext},
    );

    final qrPayload = jsonEncode({
      'v': 1,
      'link_id': linkId,
      'token': token,
      'api': ServerConfig.apiBase,
    });

    return DeviceLinkSession(
      linkId: linkId,
      token: token,
      expiresAt: DateTime.tryParse(expiresRaw)?.toLocal() ??
          DateTime.now().add(const Duration(minutes: 5)),
      qrPayload: qrPayload,
    );
  }

  Future<int> completeFromQrPayload(String raw) async {
    final map = jsonDecode(raw.trim()) as Map<String, dynamic>;
    final token = map['token'] as String? ?? '';
    if (token.isEmpty) {
      throw ApiException('二维码无效：缺少 token');
    }

    final resp = await _api.postJson(
      '/api/device-link/complete',
      body: {'token': token},
    );
    final ciphertext = resp['ciphertext'] as String? ?? '';
    if (ciphertext.isEmpty) {
      throw ApiException('服务器未返回密钥包');
    }

    final plaintext = await DeviceLinkCrypto.decrypt(token, ciphertext);
    final bundle = jsonDecode(plaintext) as Map<String, dynamic>;
    final keysRaw = bundle['keys'];
    if (keysRaw is! Map) {
      throw ApiException('密钥包格式错误');
    }
    final material = keysRaw.map(
      (key, value) => MapEntry('$key', '$value'),
    );
    await _storage.importE2eeMaterial(material);
    return material.length;
  }
}
