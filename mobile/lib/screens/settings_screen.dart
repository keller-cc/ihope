import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_version.dart';
import '../config/server_config.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_page_route.dart';
import 'change_password_screen.dart';
import 'device_link_screen.dart';
import 'devices_screen.dart';
import 'notification_settings_screen.dart';
import 'server_settings_screen.dart';
import 'storage_settings_screen.dart';
import 'version_check_screen.dart';

/// 应用设置入口（与个人资料分离）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.auth,
    required this.notification,
  });

  final AuthService auth;
  final NotificationService notification;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersionLabel = '…';

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    final label = await AppVersionInfo.displayLabel();
    if (mounted) setState(() => _appVersionLabel = label);
  }

  Future<void> _openChangePassword() async {
    final changed = await Navigator.of(context).push<bool>(
      appPageRoute(
        builder: (_) => ChangePasswordScreen(auth: widget.auth),
      ),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop('logout');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionHeader(context, '账号与安全'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('修改密码'),
            subtitle: const Text('修改后需重新登录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_openChangePassword()),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('已登录设备'),
            subtitle: const Text('查看并踢下线其它设备'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await Navigator.of(context).push<Object?>(
                appPageRoute(
                  builder: (_) => DevicesScreen(auth: widget.auth),
                ),
              );
              if (result == 'logout' && mounted) {
                Navigator.of(context).pop('logout');
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_outlined),
            title: const Text('链接设备'),
            subtitle: const Text('扫码同步加密密钥到其它设备'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                appPageRoute(
                  builder: (_) => DeviceLinkScreen(auth: widget.auth),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _sectionHeader(context, '通用'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('通知'),
            subtitle: const Text('后台新消息系统横幅'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                appPageRoute(
                  builder: (_) => NotificationSettingsScreen(
                    auth: widget.auth,
                    notification: widget.notification,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器'),
            subtitle: Text(ServerConfig.apiBase),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final result = await Navigator.of(context).push<Object?>(
                appPageRoute(
                  builder: (_) => ServerSettingsScreen(
                    auth: widget.auth,
                    requireLogoutOnSave: true,
                  ),
                ),
              );
              if (result == 'logout' && mounted) {
                Navigator.of(context).pop('logout');
              }
            },
          ),
          const Divider(height: 1),
          _sectionHeader(context, '存储与数据'),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('存储与数据管理'),
            subtitle: const Text('清除缓存、重置本地会话数据'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                appPageRoute(
                  builder: (_) => StorageSettingsScreen(auth: widget.auth),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _sectionHeader(context, '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('检查版本'),
            subtitle: Text(_appVersionLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                appPageRoute(
                  builder: (_) => VersionCheckScreen(auth: widget.auth),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
