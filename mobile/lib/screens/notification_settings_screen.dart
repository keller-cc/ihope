import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';

/// 后台消息通知开关（WebSocket 本地横幅；离线可用 QQ 门铃 / 海外 FCM）。
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    super.key,
    required this.auth,
    required this.notification,
  });

  final AuthService auth;
  final NotificationService notification;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool? _enabled;
  bool _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await widget.auth.isPushNotificationEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      if (!widget.notification.isLocalAvailable) {
        _hint = '当前平台不支持系统通知';
      } else if (!widget.notification.isRemotePushAvailable) {
        _hint =
            '离线提醒（App 被杀掉后）可在「设置 → QQ 提醒」绑定机器人门铃；'
            '海外包可配置 FCM。见 docs/推送配置指南.md';
      }
    });
  }

  Future<void> _onChanged(bool value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _hint = null;
    });

    try {
      if (value) {
        if (!widget.notification.isLocalAvailable) {
          setState(() {
            _hint = '当前平台不支持系统通知';
            _enabled = false;
          });
          return;
        }
        final ok = await widget.notification.enableNotifications();
        if (!mounted) return;
        if (!ok) {
          setState(() {
            _enabled = false;
            _hint = '未授予通知权限，可在系统设置中开启';
          });
          return;
        }
        setState(() => _enabled = true);
        if (!widget.notification.isRemotePushAvailable) {
          setState(() {
            _hint =
                '已开启后台本地通知。App 被完全杀掉后请绑定 QQ 门铃，或使用海外 FCM。';
          });
        }
      } else {
        await widget.notification.disableNotifications();
        if (!mounted) return;
        setState(() => _enabled = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _hint = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    final remote = widget.notification.isRemotePushAvailable
        ? widget.notification.remoteChannelLabel
        : '未配置（仅本地长连接）';

    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('后台新消息通知'),
            subtitle: Text(
              'App 不在前台时在系统栏显示横幅\n'
              '长连接：WebSocket + 本地通知\n'
              '离线兜底：$remote',
            ),
            value: enabled ?? false,
            onChanged: enabled == null || _busy ? null : _onChanged,
          ),
          if (_hint != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _hint!,
                style: TextStyle(
                  color: _hint!.contains('未授予') ||
                          _hint!.contains('不支持')
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              '说明：\n'
              '• 前台聊天仍走 WebSocket，当前会话内不弹横幅\n'
              '• 切到后台后 Android 会显示「正在接收新消息」并保持连接\n'
              '• 若仍收不到，请在系统设置中将 IHope 设为「不受电池优化」\n'
              '• App 被系统杀掉后，可用 QQ 门铃（设置 → QQ 提醒）或海外 FCM\n'
              '• 通知不含消息明文',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
