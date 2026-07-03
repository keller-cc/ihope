import 'package:flutter/material.dart';

import '../models/user.dart';
import '../widgets/user_avatar.dart';

/// 首页点击头像后从左侧滑入的账户面板：上方为资料/设置入口，底部为退出登录。
class AccountPanelScreen extends StatelessWidget {
  const AccountPanelScreen({
    super.key,
    required this.user,
    required this.onProfile,
    required this.onSettings,
    required this.onLogout,
  });

  final User user;
  final VoidCallback onProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width * 0.82 > 320 ? width * 0.82 : width * 0.88;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              elevation: 8,
              color: scheme.surface,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                        child: Row(
                          children: [
                            UserAvatar(
                              name: user.username,
                              imageUrl: user.avatarUrl,
                              radius: 32,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.username,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user.email,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('个人资料'),
                        subtitle: const Text('头像、用户名'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: onProfile,
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: const Text('设置'),
                        subtitle: const Text('账号、通知、存储与服务器'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: onSettings,
                      ),
                      const Spacer(),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.logout, color: scheme.error),
                        title: Text(
                          '退出登录',
                          style: TextStyle(color: scheme.error),
                        ),
                        onTap: onLogout,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
