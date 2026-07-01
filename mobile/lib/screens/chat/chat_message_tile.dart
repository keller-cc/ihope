import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../utils/announcement_read.dart';
import '../../utils/message_time.dart';
import '../../widgets/announcement_card.dart';
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
    required this.isUnmarkedUnread,
    required this.focused,
    required this.nameFor,
    required this.avatarUrlFor,
    required this.onPeerTap,
    required this.onMediaRetry,
    required this.onSendRetry,
    this.announcementReadIds = const {},
    this.onAnnouncementTap,
    this.allMessages = const [],
    this.itemKey,
  });

  final ChatMessage msg;
  final ChatMessage? prev;
  final User me;
  final ConversationItem conversation;
  final bool isGroup;
  final bool showUnreadDivider;
  final bool isUnmarkedUnread;
  final bool focused;
  final String Function(String userId) nameFor;
  final String? Function(String userId) avatarUrlFor;
  final void Function(String userId) onPeerTap;
  final Future<void> Function(String messageId) onMediaRetry;
  final void Function(ChatMessage msg) onSendRetry;
  final Set<String> announcementReadIds;
  final void Function(ChatMessage msg)? onAnnouncementTap;
  final List<ChatMessage> allMessages;
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
    } else if (msg.type == 'announcement') {
      final annUnread = AnnouncementRead.isUnread(
        announcement: msg,
        readIds: announcementReadIds,
        myUserId: me.id,
        allMessages: allMessages,
      );
      body = AnnouncementCard(
        msg: msg,
        isUnread: annUnread,
        onTap: onAnnouncementTap == null
            ? null
            : () => onAnnouncementTap!(msg),
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
        showUnreadMarker: isUnmarkedUnread,
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

/// 右侧浮动条：上方「未读消息」，下方「新消息」；底部居中为快速下滑时的「回最新」箭头。
class ChatFloatingChips extends StatelessWidget {
  const ChatFloatingChips({
    super.key,
    required this.showJumpToUnread,
    required this.showJumpToBottom,
    required this.showScrollToLatestArrow,
    required this.scrollToLatestArrowOpacity,
    required this.enterUnreadCount,
    required this.belowUnreadCount,
    required this.onJumpToUnread,
    required this.onJumpToNewMessages,
    required this.onJumpToLatest,
  });

  final bool showJumpToUnread;
  final bool showJumpToBottom;
  final bool showScrollToLatestArrow;
  final double scrollToLatestArrowOpacity;
  final int enterUnreadCount;
  final int belowUnreadCount;
  final VoidCallback onJumpToUnread;
  final VoidCallback onJumpToNewMessages;
  final VoidCallback onJumpToLatest;

  @override
  Widget build(BuildContext context) {
    /// 新消息气泡在输入框上方；快速下滑箭头紧贴输入框上沿。
    const newMessageChipBottom = 88.0;
    const scrollToLatestArrowBottom = 8.0;
    const unreadTop = 12.0;
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (showJumpToUnread)
          Positioned(
            right: 0,
            top: unreadTop,
            child: ChatScrollChip(
              label: enterUnreadCount > 0
                  ? '$enterUnreadCount条未读消息'
                  : '未读消息',
              icon: Icons.north_rounded,
              onTap: onJumpToUnread,
            ),
          ),
        if (showJumpToBottom)
          Positioned(
            right: 0,
            bottom: newMessageChipBottom,
            child: ChatScrollChip(
              label: belowUnreadCount > 0
                  ? '$belowUnreadCount条新消息'
                  : '新消息',
              icon: Icons.south_rounded,
              onTap: onJumpToNewMessages,
            ),
          ),
        if (showScrollToLatestArrow && scrollToLatestArrowOpacity > 0.01)
          Positioned(
            left: 0,
            right: 0,
            bottom: scrollToLatestArrowBottom,
            child: Center(
              child: AnimatedOpacity(
                opacity: scrollToLatestArrowOpacity.clamp(0.0, 1.0),
                duration: const Duration(milliseconds: 120),
                child: Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
                  elevation: 2,
                  shadowColor: Colors.black26,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onJumpToLatest,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: scheme.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
