import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'auth_service.dart';
import 'background_keep_alive_service.dart';
import 'local_notification_service.dart';
import 'message_notification_coordinator.dart';
import 'push_service.dart';

/// 后台通知编排：WebSocket + 本地横幅 + 前台保活；进程被杀后靠极光/FCM。
class NotificationService {
  NotificationService({PushService? push}) : push = push ?? PushService();

  final PushService push;
  final LocalNotificationService _local = LocalNotificationService();
  final BackgroundKeepAliveService _keepAlive = BackgroundKeepAliveService();
  MessageNotificationCoordinator? _coordinator;
  AuthService? _auth;

  /// 本地通知 + 保活（无需第三方密钥）。
  bool get isLocalAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 进程被杀后的离线推送通道是否已编入安装包。
  bool get isRemotePushAvailable => push.isAvailable;

  String get remoteChannelLabel => push.channelLabel;

  Future<void> initialize({
    required AuthService auth,
    void Function(String conversationId)? onOpenConversation,
  }) async {
    _auth = auth;
    await _local.initialize(onTap: onOpenConversation);
    await push.initialize(
      auth: auth,
      local: _local,
      onOpenConversation: onOpenConversation,
    );
    _coordinator = MessageNotificationCoordinator(
      auth: auth,
      local: _local,
      keepAlive: _keepAlive,
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
}
