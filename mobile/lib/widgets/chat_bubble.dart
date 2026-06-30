import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/user.dart';
import '../utils/media_payload.dart';
import '../utils/message_time.dart';
import '../widgets/member_title_badge.dart';
import '../widgets/media_message_body.dart';
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

  Widget _bubbleChild(BuildContext context) {
    final media = MediaPayload.tryParse(msg.plaintext);
    if (media != null) {
      return MediaMessageBody(msg: msg, media: media, mine: mine);
    }
    if (msg.type == 'image' ||
        msg.type == 'file' ||
        msg.type == 'audio') {
      return Text(MediaPayload.previewLabel(msg.plaintext, msg.type));
    }
    return Text(msg.displayText);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: mine ? scheme.onPrimaryContainer : scheme.onSurface,
          fontSize: 15,
        ),
        child: _bubbleChild(context),
      ),
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

    Widget nameRow() {
      return Row(
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
      );
    }

    Widget groupAvatar({
      required String userId,
      required VoidCallback? onTap,
    }) {
      return avatar(userId: userId, onTap: onTap);
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
        ),
      );
    }

    if (isGroup) {
      final avatarWidget = groupAvatar(
        userId: mine ? me.id : msg.senderId,
        onTap: !mine && onPeerTap != null
            ? () => onPeerTap!(msg.senderId)
            : null,
      );

      return Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                avatarWidget,
                const SizedBox(width: 6),
              ],
              nameRow(),
              if (mine) ...[
                const SizedBox(width: 6),
                avatarWidget,
              ],
            ],
          ),
          Padding(
            padding: EdgeInsets.only(
              left: mine ? 0 : kChatAvatarSlot,
              right: mine ? kChatAvatarSlot : 0,
            ),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.65,
                ),
                child: bubble,
              ),
            ),
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
              avatar(
                userId: msg.senderId,
                onTap: onPeerTap != null
                    ? () => onPeerTap!(msg.senderId)
                    : null,
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
        timeRow(),
      ],
    );
  }
}
