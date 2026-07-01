import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../utils/message_time.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/chat_scroll_chip.dart';

class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({
    super.key,
    required this.msg,
    required this.prev,
    required this.me,
    required this.conversation,
    required this.isGroup,
    required this.showUnreadDivider,
    required this.focused,
    required this.nameFor,
    required this.avatarUrlFor,
    required this.onPeerTap,
    required this.onMediaRetry,
    required this.onSendRetry,
    this.itemKey,
  });

  final ChatMessage msg;
  final ChatMessage? prev;
  final User me;
  final ConversationItem conversation;
  final bool isGroup;
  final bool showUnreadDivider;
  final bool focused;
  final String Function(String userId) nameFor;
  final String? Function(String userId) avatarUrlFor;
  final void Function(String userId) onPeerTap;
  final Future<void> Function(String messageId) onMediaRetry;
  final void Function(ChatMessage msg) onSendRetry;
  final Key? itemKey;

  @override
  Widget build(BuildContext context) {
    final showTime = MessageTimeFormat.shouldShowDivider(
      prev?.createdAt,
      msg.createdAt,
    );

    Widget body;
    if (msg.type == 'system') {
      body = Center(
        child: Text(
          msg.displayText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    } else {
      body = ChatBubble(
        msg: msg,
        mine: msg.senderId == me.id,
        isGroup: isGroup,
        me: me,
        senderTitle: isGroup ? conversation.memberTitle(msg.senderId) : null,
        nameFor: nameFor,
        avatarUrlFor: avatarUrlFor,
        onPeerTap: onPeerTap,
        onMediaRetry: onMediaRetry,
        onSendRetry: msg.sendStatus == MessageSendStatus.failed &&
                msg.isLocalOutgoing
            ? () => onSendRetry(msg)
            : null,
      );
    }

    final column = Column(
      key: itemKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showUnreadDivider) const UnreadMessagesDivider(),
        if (showTime)
          MessageTimeDivider(
            label: MessageTimeFormat.formatDivider(msg.createdAt),
          ),
        if (msg.type == 'system')
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: body)
        else
          Padding(padding: const EdgeInsets.only(bottom: 4), child: body),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: focused
          ? BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.35),
              ),
            )
          : null,
      padding: focused
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
          : EdgeInsets.zero,
      child: column,
    );
  }
}

class ChatFloatingChips extends StatelessWidget {
  const ChatFloatingChips({
    super.key,
    required this.showJumpToUnread,
    required this.showJumpToBottom,
    required this.enterUnreadCount,
    required this.belowUnreadCount,
    required this.onJumpToUnread,
    required this.onJumpToBottom,
  });

  final bool showJumpToUnread;
  final bool showJumpToBottom;
  final int enterUnreadCount;
  final int belowUnreadCount;
  final VoidCallback onJumpToUnread;
  final VoidCallback onJumpToBottom;

  @override
  Widget build(BuildContext context) {
    if (!showJumpToUnread && !showJumpToBottom) return const SizedBox.shrink();
    return Positioned(
      right: 0,
      top: 72,
      bottom: 72,
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showJumpToUnread)
              ChatScrollChip(
                label: '$enterUnreadCount 条未读',
                icon: Icons.arrow_upward_rounded,
                onTap: onJumpToUnread,
              ),
            if (showJumpToUnread && showJumpToBottom) const SizedBox(height: 10),
            if (showJumpToBottom)
              ChatScrollChip(
                label: belowUnreadCount > 0 ? '$belowUnreadCount 条新消息' : '回到底部',
                icon: Icons.arrow_downward_rounded,
                onTap: onJumpToBottom,
              ),
          ],
        ),
      ),
    );
  }
}
