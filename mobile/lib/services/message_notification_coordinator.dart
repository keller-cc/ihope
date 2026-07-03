import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/message.dart';
import 'auth_service.dart';
import 'background_keep_alive_service.dart';
import 'local_notification_service.dart';
import 'notification_preview.dart';

/// 是否应在后台弹出系统通知（不含极光/FCM 路径）。
bool shouldShowBackgroundNotification({
  required bool notificationsEnabled,
  required AppLifecycleState lifecycle,
  required bool conversationOpen,
  required bool isFromPeer,
}) {
  if (!notificationsEnabled) return false;
  if (!isFromPeer) return false;
  if (conversationOpen) return false;
  if (lifecycle == AppLifecycleState.resumed) return false;
  return true;
}

/// 监听 WebSocket 新消息 + App 生命周期，本机解密后展示明文本地通知。
class MessageNotificationCoordinator {
  MessageNotificationCoordinator({
    required AuthService auth,
    required LocalNotificationService local,
    BackgroundKeepAliveService? keepAlive,
  })  : _auth = auth,
        _local = local,
        _keepAlive = keepAlive ?? BackgroundKeepAliveService();

  final AuthService _auth;
  final LocalNotificationService _local;
  final BackgroundKeepAliveService _keepAlive;

  StreamSubscription<ChatMessage>? _msgSub;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  bool _enabled = false;
  bool _listening = false;

  Future<void> startIfEnabled() async {
    _enabled = await _auth.isPushNotificationEnabled();
    if (_enabled) {
      await _startListening();
    }
  }

  Future<void> start() async {
    _enabled = true;
    await _startListening();
  }

  Future<void> stop() async {
    _enabled = false;
    await _pauseListening();
  }

  /// 登出时停止监听，保留用户通知开关偏好。
  Future<void> pauseForLogout() async {
    await _pauseListening();
  }

  Future<void> _pauseListening() async {
    await _msgSub?.cancel();
    _msgSub = null;
    _listening = false;
    await _keepAlive.stop();
  }

  Future<void> _startListening() async {
    if (_listening) return;
    _listening = true;
    await _msgSub?.cancel();
    _msgSub = _auth.ws.onMessage.listen((m) => unawaited(_onMessage(m)));
    await _syncKeepAlive();
  }

  void onLifecycleChanged(AppLifecycleState state) {
    _lifecycle = state;
    unawaited(_syncKeepAlive());
  }

  Future<void> _syncKeepAlive() async {
    if (!_enabled) {
      await _keepAlive.stop();
      return;
    }
    final background = _lifecycle != AppLifecycleState.resumed;
    if (background && _keepAlive.isSupported) {
      await _keepAlive.start();
    } else {
      await _keepAlive.stop();
    }
  }

  Future<void> _onMessage(ChatMessage msg) async {
    if (!_enabled) return;

    final me = _auth.currentUser;
    if (me == null) return;
    if (msg.senderId == me.id) return;
    if (msg.type == 'announcement' || msg.type == 'system') return;
    if (_auth.isConversationOpen(msg.conversationId)) return;

    if (!shouldShowBackgroundNotification(
      notificationsEnabled: _enabled,
      lifecycle: _lifecycle,
      conversationOpen: false,
      isFromPeer: true,
    )) {
      return;
    }

    await _auth.noteIncomingMessage(msg);

    final conv = await _auth.conversationForId(msg.conversationId);
    if (conv == null) return;

    final title = conv.displayTitle(me.id);
    final body = await buildNotificationBody(_auth, conv, msg);
    final badge = _auth.totalUnreadCount();

    await _local.showMessage(
      conversationId: msg.conversationId,
      title: title,
      body: body,
      badgeNumber: badge > 0 ? badge : 1,
    );
  }
}
