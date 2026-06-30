import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/user.dart';
import '../utils/media_local_cache.dart';
import '../utils/media_payload.dart';
import '../utils/message_time.dart';
import '../widgets/member_title_badge.dart';
import '../widgets/media_message_body.dart';
import '../widgets/user_avatar.dart';

const kChatAvatarSlot = 38.0;
const kGroupNameBubbleGap = 10.0;

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
    this.onMediaRetry,
  });

  final ChatMessage msg;
  final bool mine;
  final bool isGroup;
  final User me;
  final String? senderTitle;
  final String Function(String userId) nameFor;
  final String? Function(String userId) avatarUrlFor;
  final void Function(String userId)? onPeerTap;
  final Future<void> Function(String messageId)? onMediaRetry;

  bool get _isMedia =>
      msg.type == 'image' ||
      msg.type == 'audio' ||
      msg.type == 'file' ||
      MediaLocalCache.isLocalRef(msg.plaintext) ||
      MediaPayload.tryParse(msg.plaintext) != null;

  bool get _isVoice =>
      MediaPayload.tryParse(msg.plaintext)?.kind == 'audio' ||
      msg.type == 'audio' ||
      MediaLocalCache.localKind(msg.plaintext) == 'audio';

  Widget _bubbleChild() {
    final inline = MediaPayload.tryParse(msg.plaintext);
    if (_isMedia) {
      return MediaMessageBody(
        msg: msg,
        mine: mine,
        initialMedia: inline,
        onMediaRetry: onMediaRetry,
      );
    }
    return Text(msg.displayText);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.65;
    final bubble = Container(
      padding: _isVoice
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: mine ? scheme.onPrimaryContainer : scheme.onSurface,
          fontSize: 15,
        ),
        child: _bubbleChild(),
      ),
    );
    final bubbleBox = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth),
      child: bubble,
    );

    Widget avatarFor(String userId, {VoidCallback? onTap}) {
      final child = UserAvatar(
        name: userId == me.id ? me.username : nameFor(userId),
        imageUrl: userId == me.id ? me.avatarUrl : avatarUrlFor(userId),
        radius: 16,
      );
      if (onTap == null) return child;
      return GestureDetector(onTap: onTap, child: child);
    }

    Widget timeRow() {
      return Padding(
        padding: EdgeInsets.only(
          top: 2,
          left: mine ? 0 : kChatAvatarSlot,
          right: mine ? kChatAvatarSlot : 0,
        ),
        child: Text(
          MessageTimeFormat.formatBubble(msg.createdAt),
          textAlign: mine ? TextAlign.right : TextAlign.left,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
        ),
      );
    }

    if (isGroup) {
      final userId = mine ? me.id : msg.senderId;
      final messageColumn = Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nameFor(msg.senderId),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
              ),
              if (senderTitle != null) MemberTitleBadge(title: senderTitle!),
            ],
          ),
          const SizedBox(height: kGroupNameBubbleGap),
          bubbleBox,
        ],
      );
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mine
            ? [
                messageColumn,
                const SizedBox(width: 6),
                avatarFor(userId),
              ]
            : [
                avatarFor(
                  userId,
                  onTap: onPeerTap != null
                      ? () => onPeerTap!(msg.senderId)
                      : null,
                ),
                const SizedBox(width: 6),
                messageColumn,
              ],
      );

      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: row,
          ),
          timeRow(),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (mine) const Spacer(),
            if (!mine) ...[
              avatarFor(
                msg.senderId,
                onTap: onPeerTap != null
                    ? () => onPeerTap!(msg.senderId)
                    : null,
              ),
              const SizedBox(width: 6),
            ],
            bubbleBox,
            if (mine) ...[
              const SizedBox(width: 6),
              avatarFor(me.id),
            ],
          ],
        ),
        timeRow(),
      ],
    );
  }
}
