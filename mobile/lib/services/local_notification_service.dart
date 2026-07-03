import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// WebSocket 收到消息时在系统栏显示本地通知（不依赖极光/FCM）。
class LocalNotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'ihope_messages';
  static const _channelName = '新消息';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  void Function(String conversationId)? _onTap;

  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize({
    void Function(String conversationId)? onTap,
  }) async {
    if (!isSupported || _ready) return;
    _onTap = onTap;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'App 在后台时收到新消息',
          importance: Importance.high,
        ),
      );
    }
    _ready = true;
  }

  /// 冷启动：用户点击本地通知进入 App。
  Future<String?> consumeLaunchConversationId() async {
    if (!_ready) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final payload = details!.notificationResponse?.payload;
    if (payload == null || payload.isEmpty) return null;
    return payload;
  }

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _onTap?.call(payload);
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  Future<void> showMessage({
    required String conversationId,
    required String title,
    required String body,
    int badgeNumber = 1,
  }) async {
    if (!_ready) return;

    final id = conversationId.hashCode.abs() % 100000;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'App 在后台时收到新消息',
          importance: Importance.high,
          priority: Priority.high,
          number: badgeNumber,
          groupKey: 'ihope_messages',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          badgeNumber: badgeNumber,
        ),
      ),
      payload: conversationId,
    );
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }
}
