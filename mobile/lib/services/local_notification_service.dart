import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// WebSocket 收到消息时在系统栏显示本地通知（不依赖极光/FCM）。
class LocalNotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'ihope_messages_v2';
  static const _channelName = '新消息';
  static const _summaryId = 1;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  void Function(String conversationId)? _onTap;

  /// 各会话自上次打开以来累计通知条数（用于角标 +N）。
  final Map<String, int> _conversationCounts = {};
  final Map<String, List<String>> _conversationLines = {};

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
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onResponse,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'App 在后台时收到新消息（横幅提醒）',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }
    _ready = true;
  }

  int bumpConversationCount(String conversationId) {
    return _conversationCounts.update(
      conversationId,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
  }

  Future<void> clearConversation(String conversationId) async {
    _conversationCounts.remove(conversationId);
    _conversationLines.remove(conversationId);
    if (!_ready) return;
    final id = _notificationIdFor(conversationId);
    await _plugin.cancel(id: id, tag: conversationId);
  }

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

  int _notificationIdFor(String conversationId) =>
      conversationId.hashCode.abs() % 100000 + 10;

  Future<void> showMessage({
    required String conversationId,
    required String title,
    required String body,
    int conversationMessageCount = 1,
    int totalBadge = 1,
    bool isGroup = false,
  }) async {
    if (!_ready) return;

    final lines = _conversationLines.putIfAbsent(conversationId, () => []);
    lines.add(body);
    while (lines.length > 5) {
      lines.removeAt(0);
    }

    final id = _notificationIdFor(conversationId);
    final count = conversationMessageCount > 0
        ? conversationMessageCount
        : bumpConversationCount(conversationId);

    StyleInformation? style;
    if (Platform.isAndroid && lines.length > 1) {
      style = InboxStyleInformation(
        lines.reversed.toList(),
        contentTitle: title,
        summaryText: count > 1 ? '共 $count 条新消息' : null,
      );
    }

    final displayBody = count > 1 && style == null ? '$body (+${count - 1})' : body;

    await _plugin.show(
      id: id,
      title: title,
      body: displayBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'App 在后台时收到新消息（横幅提醒）',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          number: count,
          tag: conversationId,
          groupKey: 'ihope_messages',
          channelShowBadge: true,
          enableVibration: true,
          playSound: true,
          ticker: '新消息',
          styleInformation: style,
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentBadge: true,
          presentSound: true,
          badgeNumber: totalBadge,
          threadIdentifier: conversationId,
          subtitle: count > 1 ? '$count 条新消息' : null,
        ),
      ),
      payload: conversationId,
    );

    if (Platform.isAndroid && totalBadge > 1) {
      await _showSummary(totalBadge);
    }
  }

  Future<void> _showSummary(int totalBadge) async {
    await _plugin.show(
      id: _summaryId,
      title: 'IHope',
      body: '您有 $totalBadge 条未读消息',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'App 在后台时收到新消息（横幅提醒）',
          importance: Importance.max,
          priority: Priority.max,
          groupKey: 'ihope_messages',
          setAsGroupSummary: true,
          number: totalBadge,
          channelShowBadge: true,
          autoCancel: true,
        ),
      ),
    );
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    _conversationCounts.clear();
    _conversationLines.clear();
    await _plugin.cancelAll();
  }
}
