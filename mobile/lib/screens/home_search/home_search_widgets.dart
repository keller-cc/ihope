import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../utils/chat_history_highlight.dart';
import '../../utils/media_payload.dart';
import '../../widgets/user_avatar.dart';
import 'home_search_models.dart';

String homeSearchMessagePreview(ChatMessage m) {
  if (m.type == 'text' || m.type == 'announcement' || m.type == 'system') {
    return m.displayText;
  }
  return MediaPayload.previewFromPlaintext(m.plaintext, m.type);
}

class HomeSearchContactTile extends StatelessWidget {
  const HomeSearchContactTile({
    super.key,
    required this.conversation,
    required this.meId,
    required this.onTap,
  });

  final ConversationItem conversation;
  final String meId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = conversation.displayTitle(meId);
    final avatar = conversation.displayAvatarUrl(meId);

    return ListTile(
      leading: UserAvatar(name: name, imageUrl: avatar, radius: 22),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class HomeSearchGroupTile extends StatelessWidget {
  const HomeSearchGroupTile({
    super.key,
    required this.hit,
    required this.meId,
    required this.onTap,
  });

  final HomeSearchGroupHit hit;
  final String meId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = hit.conversation;
    final name = c.displayTitle(meId);
    final count = c.members.length;
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: UserAvatar(
        name: name,
        imageUrl: c.displayAvatarUrl(meId),
        radius: 22,
      ),
      title: Text(
        '$name（$count人）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: hit.matchedMemberName == null
          ? null
          : Text(
              '包含: ${hit.matchedMemberName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
      onTap: onTap,
    );
  }
}

class HomeSearchMessageTile extends StatelessWidget {
  const HomeSearchMessageTile({
    super.key,
    required this.hit,
    required this.meId,
    required this.query,
    required this.onTap,
  });

  final HomeSearchMessageHit hit;
  final String meId;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = hit.conversation;
    final name = c.displayTitle(meId);
    final scheme = Theme.of(context).colorScheme;
    final count = hit.messages.length;

    Widget? subtitle;
    if (count == 1) {
      final text = homeSearchMessagePreview(hit.messages.first);
      subtitle = ChatHistoryHighlight.buildText(
        context,
        text,
        query,
        maxLines: 1,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      );
    } else {
      subtitle = Text(
        '$count条相关聊天记录',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      );
    }

    return ListTile(
      leading: UserAvatar(
        name: name,
        imageUrl: c.displayAvatarUrl(meId),
        radius: 22,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}

class HomeSearchSection extends StatelessWidget {
  const HomeSearchSection({
    super.key,
    required this.title,
    required this.child,
    this.onMore,
  });

  final String title;
  final Widget child;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (onMore != null)
                TextButton(
                  onPressed: onMore,
                  child: const Text('更多'),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}
