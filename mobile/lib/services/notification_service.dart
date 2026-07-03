import 'dart:async';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'auth_service.dart';
import 'background_keep_alive_service.dart';
import 'local_notification_service.dart';
import 'message_notification_coordinator.dart';
import 'push_service.dart';

/// 后台通知编排：WebSocket + 系统横幅 + 应用内横幅 + 前台保活；进程被杀后靠 FCM。
class NotificationService {
  NotificationService({PushService? push}) : push = push ?? PushService();

  final PushService push;
  final LocalNotificationService _local = LocalNotificationService();
  final BackgroundKeepAliveService _keepAlive = BackgroundKeepAliveService();
  MessageNotificationCoordinator? _coordinator;
  AuthService? _auth;

  final StreamController<InAppMessageBannerEvent> _inAppBannerController =
      StreamController<InAppMessageBannerEvent>.broadcast();

  Stream<InAppMessageBannerEvent> get inAppBannerStream =>
      _inAppBannerController.stream;

  bool get isLocalAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get isRemotePushAvailable => push.isAvailable;

  String get remoteChannelLabel => push.channelLabel;

  Future<void> initialize({
    required AuthService auth,
    void Function(String conversationId)? onOpenConversation,
  }) async {
    _auth = auth;
    await _local.initialize(onTap: onOpenConversation);
    _coordinator = MessageNotificationCoordinator(
      auth: auth,
      local: _local,
      keepAlive: _keepAlive,
      onInAppBanner: _inAppBannerController.add,
    );
    await push.initialize(
      auth: auth,
      local: _local,
      onOpenConversation: onOpenConversation,
      onForegroundMessage: (msg) => _coordinator!.handlePushMessage(msg),
    );
    await _coordinator!.startIfEnabled();

    final launchConv = await _local.consumeLaunchConversationId();
    if (launchConv != null && launchConv.isNotEmpty) {
      onOpenConversation?.call(launchConv);
    }
  }

  void onLifecycleChanged(AppLifecycleState state) {
    _coordinator?.onLifecycleChanged(state);
  }

  void onConversationOpened(String conversationId) {
    _coordinator?.onConversationOpened(conversationId);
  }

  Future<bool> enableNotifications() async {
    if (!isLocalAvailable || _auth == null) return false;

    final granted = await _local.requestPermission();
    if (!granted) return false;

    await _auth!.setPushNotificationEnabled(true);
    await _coordinator?.start();
    unawaited(push.syncTokenIfEnabled());
    return true;
  }

  Future<void> disableNotifications() async {
    await _coordinator?.stop();
    await push.disableNotifications();
    await _keepAlive.stop();
    await _local.cancelAll();
  }

  Future<void> pauseForLogout() async {
    await _coordinator?.pauseForLogout();
    await push.clearToken();
  }

  Future<void> resumeAfterLogin() async {
    await _coordinator?.startIfEnabled();
    unawaited(push.syncTokenIfEnabled());
  }

  Future<void> syncRemoteTokenIfEnabled() => push.syncTokenIfEnabled();

  Future<void> clearRemoteToken() => push.clearToken();

  void dispose() {
    unawaited(_inAppBannerController.close());
  }
}
