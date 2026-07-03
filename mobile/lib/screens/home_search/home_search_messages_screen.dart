import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../utils/chat_history_highlight.dart';
import '../../widgets/user_avatar.dart';
import 'home_search_widgets.dart';

/// 单个会话内多条命中消息。
class HomeSearchMessagesScreen extends StatelessWidget {
  const HomeSearchMessagesScreen({
    super.key,
    required this.conversation,
    required this.messages,
    required this.meId,
    required this.query,
    required this.onOpenMessage,
  });

  final ConversationItem conversation;
  final List<ChatMessage> messages;
  final String meId;
  final String query;
  final Future<void> Function(String messageId) onOpenMessage;

  @override
  Widget build(BuildContext context) {
    final title = conversation.displayTitle(meId);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        itemCount: messages.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final msg = messages[index];
          final text = homeSearchMessagePreview(msg);
          return ListTile(
            leading: UserAvatar(
              name: title,
              imageUrl: conversation.displayAvatarUrl(meId),
              radius: 20,
            ),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: ChatHistoryHighlight.buildText(
              context,
              text,
              query,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            onTap: () => onOpenMessage(msg.id),
          );
        },
      ),
    );
  }
}
