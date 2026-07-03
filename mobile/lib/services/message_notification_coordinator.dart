import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/message.dart';
import 'auth_service.dart';
import 'background_keep_alive_service.dart';
import 'local_notification_service.dart';
import 'notification_preview.dart';

/// 是否应展示应用内横幅（与系统推送开关无关）。
bool shouldShowInAppMessageBanner({
  required bool activelyViewingConversation,
  required bool isFromPeer,
}) {
  if (!isFromPeer) return false;
  if (activelyViewingConversation) return false;
  return true;
}

/// 是否应展示系统栏通知（需用户在设置中开启推送）。
bool shouldShowMessageNotification({
  required bool notificationsEnabled,
  required bool activelyViewingConversation,
  required bool isFromPeer,
}) {
  if (!notificationsEnabled) return false;
  return shouldShowInAppMessageBanner(
    activelyViewingConversation: activelyViewingConversation,
    isFromPeer: isFromPeer,
  );
}

enum MessageNotifySurface { system, inApp }

/// App 仍可见（含 Android 下拉通知栏时的 [inactive]）。
bool isAppForegroundLifecycle(AppLifecycleState lifecycle) {
  switch (lifecycle) {
    case AppLifecycleState.resumed:
    case AppLifecycleState.inactive:
      return true;
    case AppLifecycleState.paused:
    case AppLifecycleState.hidden:
    case AppLifecycleState.detached:
      return false;
  }
}

MessageNotifySurface messageNotifySurface(AppLifecycleState lifecycle) {
  if (isAppForegroundLifecycle(lifecycle)) {
    return MessageNotifySurface.inApp;
  }
  return MessageNotifySurface.system;
}

/// 应用内 QQ/微信风格顶部横幅事件。
class InAppMessageBannerEvent {
  const InAppMessageBannerEvent({
    required this.conversationId,
    required this.title,
    required this.body,
    required this.count,
  });

  final String conversationId;
  final String title;
  final String body;
  final int count;
}

/// 监听 WebSocket 新消息 + App 生命周期，展示系统通知或应用内横幅。
class MessageNotificationCoordinator {
  MessageNotificationCoordinator({
    required AuthService auth,
    required LocalNotificationService local,
    BackgroundKeepAliveService? keepAlive,
    void Function(InAppMessageBannerEvent event)? onInAppBanner,
  })  : _auth = auth,
        _local = local,
        _keepAlive = keepAlive ?? BackgroundKeepAliveService(),
        _onInAppBanner = onInAppBanner;

  final AuthService _auth;
  final LocalNotificationService _local;
  final BackgroundKeepAliveService _keepAlive;
  final void Function(InAppMessageBannerEvent event)? _onInAppBanner;

  StreamSubscription<ChatMessage>? _msgSub;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  /// 系统栏通知 / 前台保活 / FCM，由用户在设置中开启。
  bool _systemNotificationsEnabled = false;
  bool _listening = false;

  /// 前台横幅：同会话累计条数（用于 +N 展示）。
  final Map<String, int> _inAppConvCounts = {};

  /// WS 与 FCM 可能重复投递同一条消息。
  final Map<String, DateTime> _recentNotifiedMessageAt = {};

  Future<void> startIfEnabled() async {
    _systemNotificationsEnabled = await _auth.isPushNotificationEnabled();
    await _startListening();
  }

  Future<void> start() async {
    _systemNotificationsEnabled = true;
    await _startListening();
    _syncKeepAliveFlag();
    await _syncKeepAliveService();
  }

  Future<void> stop() async {
    _systemNotificationsEnabled = false;
    _inAppConvCounts.clear();
    _syncKeepAliveFlag();
    await _syncKeepAliveService();
  }

  Future<void> pauseForLogout() async {
    _systemNotificationsEnabled = false;
    await _pauseListening();
    _inAppConvCounts.clear();
    _auth.setBackgroundKeepAlive(false);
  }

  void onConversationOpened(String conversationId) {
    _inAppConvCounts.remove(conversationId);
    unawaited(_local.clearConversation(conversationId));
  }

  /// FCM 前台投递，与 WebSocket 共用展示逻辑。
  Future<void> handlePushMessage(ChatMessage msg) => _onMessage(msg);

  Future<void> _pauseListening() async {
    await _msgSub?.cancel();
    _msgSub = null;
    _listening = false;
    _auth.setBackgroundKeepAlive(false);
    await _keepAlive.stop();
  }

  Future<void> _startListening() async {
    if (_listening) return;
    _listening = true;
    await _msgSub?.cancel();
    _msgSub = _auth.ws.onMessage.listen((m) => unawaited(_onMessage(m)));
    _syncKeepAliveFlag();
    await _syncKeepAliveService();
  }

  void onLifecycleChanged(AppLifecycleState state) {
    _lifecycle = state;
    _auth.setAppInForeground(isAppForegroundLifecycle(state));
    _syncKeepAliveFlag();
    if (state == AppLifecycleState.resumed) {
      _inAppConvCounts.clear();
    }
    unawaited(_syncKeepAliveService());
  }

  /// 同步标记（须在 [AuthService.ws.suspendReconnect] 之前）。
  void _syncKeepAliveFlag() {
    if (!_listening) {
      _auth.setBackgroundKeepAlive(false);
      return;
    }
    final background = !isAppForegroundLifecycle(_lifecycle);
    _auth.setBackgroundKeepAlive(background && _keepAlive.isSupported);
  }

  Future<void> _syncKeepAliveService() async {
    if (!_listening) {
      await _keepAlive.stop();
      return;
    }
    final background = !isAppForegroundLifecycle(_lifecycle);
    if (background && _keepAlive.isSupported) {
      await _keepAlive.start();
    } else {
      await _keepAlive.stop();
    }
  }

  bool _isDuplicateNotify(ChatMessage msg) {
    if (msg.id.isEmpty) return false;
    final now = DateTime.now();
    final seenAt = _recentNotifiedMessageAt[msg.id];
    if (seenAt != null && now.difference(seenAt) < const Duration(seconds: 15)) {
      return true;
    }
    _recentNotifiedMessageAt[msg.id] = now;
    if (_recentNotifiedMessageAt.length > 200) {
      _recentNotifiedMessageAt.removeWhere(
        (_, at) => now.difference(at) > const Duration(minutes: 1),
      );
    }
    return false;
  }

  Future<void> _onMessage(ChatMessage msg) async {
    if (!_listening) return;
    if (_isDuplicateNotify(msg)) return;

    final me = _auth.currentUser;
    if (me == null) return;
    if (msg.senderId == me.id) return;
    if (msg.type == 'announcement' || msg.type == 'system') return;

    final activelyViewing =
        _auth.isActivelyViewingConversation(msg.conversationId);
    if (!shouldShowInAppMessageBanner(
      activelyViewingConversation: activelyViewing,
      isFromPeer: true,
    )) {
      return;
    }

    final conv = await _auth.conversationForId(msg.conversationId);
    if (conv == null) return;

    final title = conv.displayTitle(me.id);
    final body = await buildNotificationBody(_auth, conv, msg);
    final surface = messageNotifySurface(_lifecycle);

    if (surface == MessageNotifySurface.system) {
      if (!shouldShowMessageNotification(
        notificationsEnabled: _systemNotificationsEnabled,
        activelyViewingConversation: activelyViewing,
        isFromPeer: true,
      )) {
        return;
      }
      final convCount = _local.bumpConversationCount(msg.conversationId);
      final totalBadge = _auth.totalUnreadCount();
      await _local.showMessage(
        conversationId: msg.conversationId,
        title: title,
        body: body,
        conversationMessageCount: convCount,
        totalBadge: totalBadge > 0 ? totalBadge : convCount,
        isGroup: conv.type == 'group',
      );
      return;
    }

    final count = (_inAppConvCounts[msg.conversationId] ?? 0) + 1;
    _inAppConvCounts[msg.conversationId] = count;
    _onInAppBanner?.call(
      InAppMessageBannerEvent(
        conversationId: msg.conversationId,
        title: title,
        body: body,
        count: count,
      ),
    );
  }
}

/// @Deprecated 兼容旧测试名
@Deprecated('Use shouldShowMessageNotification')
bool shouldShowBackgroundNotification({
  required bool notificationsEnabled,
  required AppLifecycleState lifecycle,
  required bool conversationOpen,
  required bool isFromPeer,
}) {
  final activelyViewing =
      conversationOpen && lifecycle == AppLifecycleState.resumed;
  return shouldShowMessageNotification(
    notificationsEnabled: notificationsEnabled,
    activelyViewingConversation: activelyViewing,
    isFromPeer: isFromPeer,
  );
}
