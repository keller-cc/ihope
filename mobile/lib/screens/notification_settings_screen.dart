import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/notification_service.dart';

/// 后台消息通知开关。
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

    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('新消息通知'),
            subtitle: const Text('前台应用内横幅；后台系统通知栏'),
            value: enabled ?? true,
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
        ],
      ),
    );
  }
}
