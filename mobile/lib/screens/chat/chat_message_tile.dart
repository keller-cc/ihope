import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../utils/announcement_read.dart';
import '../../utils/message_time.dart';
import '../../widgets/announcement_card.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/chat_scroll_chip.dart';
import '../../utils/media_retry_callback.dart';
import 'chat_image_launcher.dart';

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
  final bool focused;
  final String Function(String userId) nameFor;
  final String? Function(String userId) avatarUrlFor;
  final void Function(String userId) onPeerTap;
  final MediaRetryCallback onMediaRetry;
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
        child: SelectableText(
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
        imageGallery: ChatImageLauncher.galleryFromMessages(allMessages),
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

    return _MessageFocusShell(
      focused: focused,
      child: column,
    );
  }
}

/// 定位高亮：快速淡入、稍慢淡出，避免生硬消失。
class _MessageFocusShell extends StatefulWidget {
  const _MessageFocusShell({
    required this.focused,
    required this.child,
  });

  final bool focused;
  final Widget child;

  @override
  State<_MessageFocusShell> createState() => _MessageFocusShellState();
}

class _MessageFocusShellState extends State<_MessageFocusShell>
    with SingleTickerProviderStateMixin {
  static const _fadeIn = Duration(milliseconds: 180);
  static const _fadeOut = Duration(milliseconds: 420);

  late final AnimationController _controller;
  late final Animation<double> _strength;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _fadeIn);
    _strength = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    if (widget.focused) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _MessageFocusShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused == oldWidget.focused) return;
    if (widget.focused) {
      _controller.duration = _fadeIn;
      _controller.forward();
    } else {
      _controller.duration = _fadeOut;
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _strength,
      builder: (context, child) {
        final v = _strength.value;
        if (v <= 0.001) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: child,
          );
        }
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: EdgeInsets.symmetric(horizontal: 4 * v, vertical: 2 * v),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.09 * v),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.20 * v),
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
