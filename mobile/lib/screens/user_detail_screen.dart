import 'package:flutter/material.dart';

import '../crypto/identity.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../widgets/member_title_badge.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

/// 聊天中点击他人头像进入的用户详情（只读）。
class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({
    super.key,
    required this.auth,
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.identityPublicKey = '',
    this.groupContext,
  });

  final AuthService auth;
  final String userId;
  final String username;
  final String? avatarUrl;
  final String identityPublicKey;
  final ConversationItem? groupContext;

  bool get _isSelf => auth.currentUser?.id == userId;

  String? get _memberTitle {
    if (groupContext == null) return null;
    return groupContext!.memberTitle(userId);
  }

  Future<void> _startPrivateChat(BuildContext context) async {
    try {
      final conv = await auth.conversations.createPrivateChat(userId);
      if (!context.mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(auth: auth, conversation: conv),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final e2eeReady = isValidIdentityPublicKey(identityPublicKey);
    return Scaffold(
      appBar: AppBar(title: const Text('用户详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: UserAvatar(
              name: username,
              imageUrl: avatarUrl,
              radius: 48,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (_memberTitle != null)
                  MemberTitleBadge(title: _memberTitle!),
              ],
            ),
          ),
          if (groupContext != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                '来自群聊「${groupContext!.name ?? '群聊'}」',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _InfoTile(
            icon: Icons.fingerprint,
            label: '端到端加密',
            value: e2eeReady ? '已配置身份密钥' : '尚未配置（需重新登录）',
          ),
          if (!_isSelf) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _startPrivateChat(context),
              icon: const Icon(Icons.chat),
              label: const Text('发起单聊'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

/// 从会话成员打开详情页。
void openUserDetailFromMember(
  BuildContext context, {
  required AuthService auth,
  required ConversationMember member,
  ConversationItem? groupContext,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => UserDetailScreen(
        auth: auth,
        userId: member.userId,
        username: member.username,
        avatarUrl: member.avatarUrl,
        identityPublicKey: member.identityPublicKey,
        groupContext: groupContext,
      ),
    ),
  );
}
