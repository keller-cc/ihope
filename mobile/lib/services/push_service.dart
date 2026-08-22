import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/push_config.dart';
import '../models/message.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';
import 'remote_push_handler.dart';

export 'remote_push_handler.dart' show firebaseMessagingBackgroundHandler;

/// 离线兜底：FCM（海外）传密文，客户端解密后本地展示明文通知。
/// 国内推荐 QQ 门铃（不依赖本类）；未配置时仅 WebSocket + 本地通知。
class PushService {
  PushService({PushChannel? channel}) : _channel = channel ?? pushChannel;

  final PushChannel _channel;

  bool _ready = false;
  bool _permissionGranted = false;
  AuthService? _auth;
  LocalNotificationService? _local;
  void Function(String conversationId)? _onOpenConversation;
  Future<void> Function(ChatMessage msg)? _onForegroundMessage;

  PushChannel get channel => _channel;

  String get channelLabel => pushChannelLabel;

  bool get isAvailable {
    if (_channel == PushChannel.none) return false;
    return _ready;
  }

  Future<void> initialize({
    required AuthService auth,
    required LocalNotificationService local,
    void Function(String conversationId)? onOpenConversation,
    Future<void> Function(ChatMessage msg)? onForegroundMessage,
  }) async {
    _auth = auth;
    _local = local;
    _onOpenConversation = onOpenConversation;
    _onForegroundMessage = onForegroundMessage;

    if (kIsWeb || _channel == PushChannel.none) return;

    if (_channel == PushChannel.fcm) {
      await _initFcm();
    }
  }

  Future<void> _initFcm() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('PushService(FCM): Firebase not configured ($e)');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_onFcmForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onFcmOpen);
    FirebaseMessaging.instance.onTokenRefresh
        .listen((_) => unawaited(syncTokenIfEnabled()));

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleExtras(initial.data);
    }

    _ready = true;
    await _refreshFcmPermission();
    if (_permissionGranted) {
      unawaited(syncTokenIfEnabled());
    }
  }

  Future<void> _onFcmForeground(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    final msg = chatMessageFromPushData(data);
    if (msg == null) return;
    final handler = _onForegroundMessage;
    if (handler != null) {
      await handler(msg);
      return;
    }
    await _presentPushData(data);
  }

  Future<void> _presentPushData(Map<String, dynamic> data) async {
    final local = _local;
    final auth = _auth;
    if (local == null || auth == null) return;
    await presentRemotePush(data, local: local, auth: auth);
  }

  Future<void> _refreshFcmPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    _permissionGranted = settings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> enableNotifications() async {
    if (_auth == null) return false;

    if (!_ready || _channel == PushChannel.none) {
      return false;
    }

    if (_channel == PushChannel.fcm) {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _permissionGranted = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } else {
      _permissionGranted = true;
    }

    if (!_permissionGranted) return false;

    await _auth!.setPushNotificationEnabled(true);
    await syncToken();
    return true;
  }

  Future<void> disableNotifications() async {
    if (_auth == null) return;
    await _auth!.setPushNotificationEnabled(false);
    await clearToken();
  }

  Future<void> syncTokenIfEnabled() async {
    if (!_ready || _auth == null) return;
    if (!await _auth!.isPushNotificationEnabled()) return;
    if (_channel == PushChannel.fcm) {
      await _refreshFcmPermission();
    }
    if (!_permissionGranted) return;
    await syncToken();
  }

  Future<void> syncToken() async {
    if (!_ready || _auth == null) return;

    if (_channel == PushChannel.fcm) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token == null || token.isEmpty) return;
        await _auth!.registerPushToken(
          pushToken: token,
          platform: pushPlatformTag(_channel),
        );
      } catch (e) {
        debugPrint('PushService(FCM): sync token failed: $e');
      }
    }
  }

  Future<void> clearToken() async {
    if (_auth == null) return;
    try {
      await _auth!.registerPushToken(pushToken: '', platform: '');
      if (_ready && _channel == PushChannel.fcm) {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (e) {
      debugPrint('PushService: clear token failed: $e');
    }
  }

  void _onFcmOpen(RemoteMessage message) {
    _handleExtras(message.data);
  }

  void _handleExtras(Map<String, dynamic> data) {
    final convId = data['conversation_id'];
    if (convId is String && convId.isNotEmpty) {
      _onOpenConversation?.call(convId);
    }
  }
}
