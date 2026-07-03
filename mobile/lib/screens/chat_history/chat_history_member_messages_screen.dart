import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import 'widgets/chat_history_result_tile.dart';

/// 某成员的发言列表。
class ChatHistoryMemberMessagesScreen extends StatelessWidget {
  const ChatHistoryMemberMessagesScreen({
    super.key,
    required this.auth,
    required this.conversation,
    required this.member,
    required this.messages,
    required this.onJump,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final ConversationMember member;
  final List<ChatMessage> messages;
  final void Function(String? messageId) onJump;

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation.type == 'group';

    return Scaffold(
      appBar: AppBar(title: Text('${member.username}的发言')),
      body: messages.isEmpty
          ? const Center(child: Text('暂无消息'))
          : ListView.separated(
              itemCount: messages.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final msg = messages[index];
                return ChatHistoryResultTile(
                  msg: msg,
                  name: member.username,
                  senderTitle: isGroup
                      ? conversation.memberTitle(member.userId)
                      : null,
                  avatarUrl: member.avatarUrl,
                  onTap: () {
                    Navigator.of(context).pop();
                    onJump(msg.id);
                  },
                );
              },
            ),
    );
  }
}
