import 'api_client.dart';

class SignalPreKeyBundle {
  SignalPreKeyBundle({
    required this.registrationId,
    required this.deviceId,
    required this.signalDeviceId,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    required this.identityKey,
    this.preKeyId,
    this.preKeyPublic,
  });

  final int registrationId;
  final String deviceId;
  final int signalDeviceId;
  final int? preKeyId;
  final String? preKeyPublic;
  final int signedPreKeyId;
  final String signedPreKeyPublic;
  final String signedPreKeySignature;
  final String identityKey;

  factory SignalPreKeyBundle.fromJson(Map<String, dynamic> json) {
    return SignalPreKeyBundle(
      registrationId: json['registration_id'] as int,
      deviceId: json['device_id'] as String? ?? '',
      signalDeviceId: json['signal_device_id'] as int? ?? 1,
      preKeyId: json['pre_key_id'] as int?,
      preKeyPublic: json['pre_key_public'] as String?,
      signedPreKeyId: json['signed_pre_key_id'] as int,
      signedPreKeyPublic: json['signed_pre_key_public'] as String,
      signedPreKeySignature: json['signed_pre_key_signature'] as String,
      identityKey: json['identity_key'] as String,
    );
  }
}

/// Signal KDS：预密钥包上传与拉取。
class SignalKdsService {
  SignalKdsService(this.api);

  final ApiClient api;

  Future<void> uploadKeys({
    required String deviceId,
    required int signalDeviceId,
    required int registrationId,
    required String identityKey,
    required int signedPreKeyId,
    required String signedPreKeyPublic,
    required String signedPreKeySignature,
    required List<Map<String, dynamic>> oneTimePreKeys,
  }) async {
    await api.putJson('/api/users/me/signal-keys', body: {
      'device_id': deviceId,
      'signal_device_id': signalDeviceId,
      'registration_id': registrationId,
      'identity_key': identityKey,
      'signed_pre_key_id': signedPreKeyId,
      'signed_pre_key_public': signedPreKeyPublic,
      'signed_pre_key_signature': signedPreKeySignature,
      'one_time_pre_keys': oneTimePreKeys,
    });
  }

  Future<SignalPreKeyBundle> fetchBundle(String userId) async {
    final data = await api.getJson('/api/users/$userId/signal-bundle');
    return SignalPreKeyBundle.fromJson(data);
  }
}
