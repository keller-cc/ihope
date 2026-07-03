import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/push_config.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';
import 'remote_push_handler.dart';

export 'remote_push_handler.dart' show firebaseMessagingBackgroundHandler;

/// 离线兜底：极光 / FCM 仅传密文，客户端解密后本地展示明文通知。
class PushService {
  PushService({PushChannel? channel})
      : _channel = channel ?? pushChannel;

  final PushChannel _channel;
  final JPushFlutterInterface _jpush = JPush.newJPush();

  bool _ready = false;
  bool _permissionGranted = false;
  AuthService? _auth;
  LocalNotificationService? _local;
  void Function(String conversationId)? _onOpenConversation;

  PushChannel get channel => _channel;

  String get channelLabel => pushChannelLabel;

  bool get isAvailable => _channel != PushChannel.none;

  Future<void> initialize({
    required AuthService auth,
    required LocalNotificationService local,
    void Function(String conversationId)? onOpenConversation,
  }) async {
    _auth = auth;
    _local = local;
    _onOpenConversation = onOpenConversation;

    if (kIsWeb || _channel == PushChannel.none) return;

    switch (_channel) {
      case PushChannel.fcm:
        await _initFcm();
      case PushChannel.jpush:
        await _initJpush();
      case PushChannel.none:
        break;
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

  Future<void> _initJpush() async {
    final appKey = kJPushAppKey;
    if (appKey.isEmpty && !Platform.isAndroid) {
      debugPrint('PushService(JPush): JPUSH_APP_KEY missing');
      return;
    }

    _jpush.addEventHandler(
      onOpenNotification: (event) async {
        _handleJpushOpen(event);
      },
      onReceiveNotification: (event) async {
        await _onJpushPayload(_extractJpushMap(event));
      },
      onReceiveMessage: (event) async {
        await _onJpushPayload(_extractJpushMap(event));
      },
    );

    _jpush.setUnShowAtTheForeground(unShow: true);

    _jpush.setup(
      appKey: appKey,
      channel: 'ihope',
      production: !kDebugMode,
      debug: kDebugMode,
    );

    _ready = true;
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      _permissionGranted = status.isGranted;
    } else {
      _permissionGranted = true;
    }
    if (_permissionGranted) {
      unawaited(syncTokenIfEnabled());
    }
  }

  Future<void> _onFcmForeground(RemoteMessage message) async {
    await _presentPushData(Map<String, dynamic>.from(message.data));
  }

  Future<void> _onJpushPayload(Map<String, dynamic>? data) async {
    if (data == null || data.isEmpty) return;
    await _presentPushData(data);
  }

  Future<void> _presentPushData(Map<String, dynamic> data) async {
    final local = _local;
    final auth = _auth;
    if (local == null || auth == null) return;
    await presentRemotePush(data, local: local, auth: auth);
  }

  Map<String, dynamic>? _extractJpushMap(Map<String, dynamic> event) {
    final extras = event['extras'];
    if (extras is Map) {
      return Map<String, dynamic>.from(extras);
    }
    final androidExtras = event['extrasMap'] ?? event['nExtras'];
    if (androidExtras is Map) {
      return Map<String, dynamic>.from(androidExtras);
    }
    if (event.containsKey('ciphertext') && event.containsKey('conversation_id')) {
      return Map<String, dynamic>.from(event);
    }
    return null;
  }

  Future<void> _refreshFcmPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    _permissionGranted = settings.authorizationStatus ==
            AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> enableNotifications() async {
    if (!_ready || _auth == null || _channel == PushChannel.none) {
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
    } else if (_channel == PushChannel.jpush && Platform.isAndroid) {
      final status = await Permission.notification.request();
      _permissionGranted = status.isGranted;
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
    try {
      final token = await _readToken();
      if (token == null || token.isEmpty) return;
      await _auth!.registerPushToken(
        pushToken: token,
        platform: pushPlatformTag(_channel),
      );
    } catch (e) {
      debugPrint('PushService: sync token failed: $e');
    }
  }

  Future<String?> _readToken() async {
    switch (_channel) {
      case PushChannel.fcm:
        return FirebaseMessaging.instance.getToken();
      case PushChannel.jpush:
        for (var i = 0; i < 8; i++) {
          final rid = await _jpush.getRegistrationID();
          if (rid.isNotEmpty) return rid;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        return null;
      case PushChannel.none:
        return null;
    }
  }

  Future<void> clearToken() async {
    if (!_ready || _auth == null) return;
    try {
      await _auth!.registerPushToken(pushToken: '', platform: '');
      if (_channel == PushChannel.fcm) {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (e) {
      debugPrint('PushService: clear token failed: $e');
    }
  }

  void _onFcmOpen(RemoteMessage message) {
    _handleExtras(message.data);
  }

  void _handleJpushOpen(Map<String, dynamic> message) {
    final map = _extractJpushMap(message);
    if (map != null) {
      _handleExtras(map);
    }
  }

  void _handleExtras(Map<String, dynamic> data) {
    final convId = data['conversation_id'];
    if (convId is String && convId.isNotEmpty) {
      _onOpenConversation?.call(convId);
    }
  }
}
