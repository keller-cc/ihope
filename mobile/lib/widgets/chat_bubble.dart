import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/user.dart';
import '../utils/message_time.dart';
import '../widgets/member_title_badge.dart';
import '../widgets/user_avatar.dart';

const kChatAvatarSlot = 38.0;

class MessageTimeDivider extends StatelessWidget {
  const MessageTimeDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.msg,
    required this.mine,
    required this.isGroup,
    required this.me,
    required this.senderTitle,
    required this.nameFor,
    required this.avatarUrlFor,
    this.onPeerTap,
  });

  final ChatMessage msg;
  final bool mine;
  final bool isGroup;
  final User me;
  final String? senderTitle;
  final String Function(String userId) nameFor;
  final String? Function(String userId) avatarUrlFor;
  final void Function(String userId)? onPeerTap;

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(msg.displayText),
    );

    Widget avatar({required VoidCallback? onTap, required String userId}) {
      final child = UserAvatar(
        name: userId == me.id ? me.username : nameFor(userId),
        imageUrl: userId == me.id ? me.avatarUrl : avatarUrlFor(userId),
        radius: 16,
      );
      if (onTap == null) return child;
      return GestureDetector(onTap: onTap, child: child);
    }

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (isGroup && !mine)
          Padding(
            padding: const EdgeInsets.only(left: kChatAvatarSlot, bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nameFor(msg.senderId),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (senderTitle != null) MemberTitleBadge(title: senderTitle!),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (mine) const Spacer(),
            if (!mine) ...[
              avatar(
                userId: msg.senderId,
                onTap: onPeerTap != null ? () => onPeerTap!(msg.senderId) : null,
              ),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.65,
              ),
              child: bubble,
            ),
            if (mine) ...[
              const SizedBox(width: 6),
              avatar(userId: me.id, onTap: null),
            ],
          ],
        ),
        Padding(
          padding: EdgeInsets.only(
            top: 2,
            left: mine ? 0 : kChatAvatarSlot,
            right: mine ? kChatAvatarSlot : 0,
          ),
          child: Text(
            MessageTimeFormat.formatBubble(msg.createdAt),
            textAlign: mine ? TextAlign.right : TextAlign.left,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
          ),
        ),
      ],
    );
  }
}
