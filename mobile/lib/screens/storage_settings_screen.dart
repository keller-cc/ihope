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
            child: const Text('确定'),
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
      title: '清除缓存',
      body: '将删除本地消息缓存、聊天图片/语音文件、最近使用的表情。'
          '不会退出登录，也不会删除加密密钥。',
      action: widget.auth.clearLocalCache,
      success: '缓存已清除',
    );
  }

  Future<void> _clearLocalData() async {
    await _confirmAndRun(
      title: '清除本地数据',
      body: '除「清除缓存」内容外，还会删除会话列表快照、已读游标、置顶等本地偏好。'
          '仍保留登录状态与端到端加密密钥；下次打开会从服务器重新同步。',
      action: widget.auth.clearLocalData,
      success: '本地数据已清除',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('存储与缓存')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const ListTile(
            title: Text('说明'),
            subtitle: Text(
              '以下操作不会退出登录，也不会删除账号或加密密钥。'
              '清除后聊天记录需重新从服务器加载或解密。',
            ),
          ),
          const Divider(),
          ListTile(
            enabled: !_busy,
            title: const Text('清除缓存'),
            subtitle: const Text('消息缓存、媒体文件、最近表情'),
            trailing: _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            onTap: _busy ? null : _clearCache,
          ),
          ListTile(
            enabled: !_busy,
            title: const Text('清除本地数据'),
            subtitle: const Text('缓存 + 会话快照、已读游标、置顶等'),
            trailing: const Icon(Icons.cleaning_services_outlined),
            onTap: _busy ? null : _clearLocalData,
          ),
        ],
      ),
    );
  }
}
