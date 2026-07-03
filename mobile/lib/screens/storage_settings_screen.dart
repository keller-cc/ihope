import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// 本地存储与缓存管理（不退出登录）。
class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  bool _busy = false;

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required Future<void> Function() action,
    required String success,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearCache() async {
    await _confirmAndRun(
      title: '清除聊天与媒体缓存',
      body: '将删除本机保存的消息副本、图片/语音/文件缓存，以及最近使用的表情。\n\n'
          '不会退出登录，也不会删除加密密钥或会话列表。',
      action: widget.auth.clearLocalCache,
      success: '聊天与媒体缓存已清除，打开会话时将重新加载',
    );
  }

  Future<void> _clearLocalData() async {
    await _confirmAndRun(
      title: '重置本地会话数据',
      body: '将清除「聊天与媒体缓存」的全部内容，并额外删除：\n'
          '· 首页会话列表快照\n'
          '· 各会话已读位置\n'
          '· 置顶、归档等本地偏好\n\n'
          '仍保留登录与加密密钥；返回首页后会从服务器重新同步。',
      action: widget.auth.clearLocalData,
      success: '本地会话数据已重置，请下拉刷新首页会话',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('存储与数据')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '这些操作只影响本机',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '不会删除云端聊天记录或账号，也不会退出登录。'
                    '清除后部分聊天内容需重新从服务器加载或解密。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            busy: _busy,
            icon: Icons.chat_bubble_outline,
            iconColor: scheme.tertiary,
            title: '清除聊天与媒体缓存',
            effect: '打开聊天时消息需重新加载；图片/语音/文件需重新下载',
            removes: const [
              '本地消息副本',
              '图片、语音、文件缓存',
              '最近使用的表情',
            ],
            keeps: const [
              '登录状态',
              '加密密钥',
              '会话列表与置顶',
              '已读位置',
            ],
            buttonLabel: '清除缓存',
            onPressed: _clearCache,
          ),
          const SizedBox(height: 16),
          _ActionCard(
            busy: _busy,
            icon: Icons.restart_alt,
            iconColor: scheme.error,
            title: '重置本地会话数据',
            effect: '首页会话列表会从服务器重新拉取；未读数与已读状态重新计算',
            removes: const [
              '上述「清除缓存」的全部内容',
              '首页会话列表快照',
              '各会话已读游标',
              '置顶、归档等本地偏好',
            ],
            keeps: const [
              '登录状态',
              '端到端加密密钥',
            ],
            buttonLabel: '重置本地数据',
            destructive: true,
            onPressed: _clearLocalData,
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.busy,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.effect,
    required this.removes,
    required this.keeps,
    required this.buttonLabel,
    required this.onPressed,
    this.destructive = false,
  });

  final bool busy;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String effect;
  final List<String> removes;
  final List<String> keeps;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: iconColor.withValues(alpha: 0.12),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '点击后：$effect',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _BulletSection(
              label: '会删除',
              color: destructive ? scheme.error : scheme.onSurfaceVariant,
              items: removes,
            ),
            const SizedBox(height: 8),
            _BulletSection(
              label: '不会删除',
              color: scheme.primary,
              items: keeps,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: busy ? null : onPressed,
              style: destructive
                  ? FilledButton.styleFrom(
                      foregroundColor: scheme.onErrorContainer,
                      backgroundColor: scheme.errorContainer,
                    )
                  : null,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletSection extends StatelessWidget {
  const _BulletSection({
    required this.label,
    required this.color,
    required this.items,
  });

  final String label;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('· ', style: TextStyle(color: color)),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
