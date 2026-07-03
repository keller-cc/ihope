import 'package:intl/intl.dart';

import '../services/api_client.dart';
import '../services/auth_storage.dart';

class UserDeviceItem {
  UserDeviceItem({
    required this.deviceId,
    this.deviceName,
    this.platform = '',
    required this.lastActiveAt,
    required this.hasSession,
    required this.isCurrent,
  });

  final String deviceId;
  final String? deviceName;
  final String platform;
  final DateTime lastActiveAt;
  final bool hasSession;
  final bool isCurrent;

  factory UserDeviceItem.fromJson(Map<String, dynamic> json) {
    return UserDeviceItem(
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String?,
      platform: json['platform'] as String? ?? '',
      lastActiveAt: DateTime.tryParse(json['last_active_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      hasSession: json['has_session'] as bool? ?? false,
      isCurrent: json['is_current'] as bool? ?? false,
    );
  }

  String displayName(AuthStorage storage) {
    if (deviceName != null && deviceName!.trim().isNotEmpty) {
      return deviceName!.trim();
    }
    return deviceId;
  }

  String subtitle() {
    final parts = <String>[];
    if (platform.isNotEmpty) parts.add(platform);
    parts.add(DateFormat('yyyy-MM-dd HH:mm').format(lastActiveAt.toLocal()));
    if (hasSession) parts.add('已登录');
    if (isCurrent) parts.add('本机');
    return parts.join(' · ');
  }
}

class DeviceService {
  DeviceService(this.api);

  final ApiClient api;

  Future<List<UserDeviceItem>> listDevices() async {
    final data = await api.getJson('/api/devices');
    final raw = data['devices'];
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(UserDeviceItem.fromJson)
        .toList();
  }

  Future<void> kickDevice(String deviceId) async {
    await api.deleteJson('/api/devices/$deviceId');
  }
}
