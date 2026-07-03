import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../screens/chat_history/chat_history_hub_screen.dart';
import '../screens/chat_history/chat_history_jump.dart';
import 'app_page_route.dart';

/// 单聊/群聊共用的置顶与聊天记录查找入口。
class ConversationCommonSettings extends StatelessWidget {
  const ConversationCommonSettings({
    super.key,
    required this.auth,
    required this.conversation,
    required this.pinned,
    required this.onPinChanged,
    this.enabled = true,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final bool pinned;
  final ValueChanged<bool> onPinChanged;
  final bool enabled;

  Future<void> _openSearch(BuildContext context) async {
    final jump = await Navigator.of(context).push<ChatHistoryJump>(
      appPageRoute(
        builder: (_) => ChatHistoryHubScreen(
          auth: auth,
          conversation: conversation,
        ),
      ),
    );
    if (jump != null && context.mounted) {
      Navigator.of(context).pop(jump);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          secondary: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
          title: const Text('置顶会话'),
          subtitle: const Text('置顶后在首页列表靠前显示'),
          value: pinned,
          onChanged: enabled ? onPinChanged : null,
        ),
        ListTile(
          leading: const Icon(Icons.search),
          title: const Text('查找聊天记录'),
          subtitle: const Text('按日期、成员、图片与文件查找'),
          onTap: enabled ? () => _openSearch(context) : null,
        ),
      ],
    );
  }
}
