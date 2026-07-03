import 'package:flutter/material.dart';

import '../../../models/message.dart';
import '../../../utils/chat_history_highlight.dart';
import '../../../utils/media_payload.dart';
import '../../../utils/message_time.dart';
import '../../../widgets/member_title_badge.dart';
import '../../../widgets/user_avatar.dart';

/// 聊天记录查找结果行。
class ChatHistoryResultTile extends StatelessWidget {
  const ChatHistoryResultTile({
    super.key,
    required this.msg,
    required this.name,
    required this.onTap,
    this.senderTitle,
    this.avatarUrl,
    this.highlightQuery,
  });

  final ChatMessage msg;
  final String name;
  final String? senderTitle;
  final String? avatarUrl;
  final String? highlightQuery;
  final VoidCallback onTap;

  String get _preview {
    if (msg.type == 'text' || msg.type == 'announcement' || msg.type == 'system') {
      return msg.displayText;
    }
    return MediaPayload.previewFromPlaintext(msg.plaintext, msg.type);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = MessageTimeFormat.formatList(msg.createdAt);

    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: name, imageUrl: avatarUrl, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (senderTitle != null) ...[
                                const SizedBox(width: 6),
                                MemberTitleBadge(title: senderTitle!),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ChatHistoryHighlight.buildText(
                      context,
                      _preview,
                      highlightQuery ?? '',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
