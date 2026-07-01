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
    this.onSendRetry,
    this.showUnreadMarker = false,
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
  final VoidCallback? onSendRetry;
  final bool showUnreadMarker;

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

  Widget _unreadMarkerDot(ColorScheme scheme) {
    if (!showUnreadMarker || mine) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4, top: 14),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: scheme.error,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _sendStatusIndicator(ColorScheme scheme) {
    if (!mine) return const SizedBox.shrink();
    switch (msg.sendStatus) {
      case MessageSendStatus.sent:
        return const SizedBox.shrink();
      case MessageSendStatus.sending:
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      case MessageSendStatus.failed:
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: onSendRetry,
            behavior: HitTestBehavior.opaque,
            child: Icon(
              Icons.error_outline,
              size: 22,
              color: scheme.error,
            ),
          ),
        );
    }
  }

  Widget _bubbleWithStatus(Widget bubbleBox, ColorScheme scheme) {
    if (!mine || msg.sendStatus == MessageSendStatus.sent) {
      return bubbleBox;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _sendStatusIndicator(scheme),
        bubbleBox,
      ],
    );
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
    final bubbleWithStatus = _bubbleWithStatus(bubbleBox, scheme);

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
      final nameStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          );
      final headerChildren = <Widget>[
        if (mine && senderTitle != null) ...[
          MemberTitleBadge(title: senderTitle!),
          const SizedBox(width: 4),
        ],
        Text(nameFor(msg.senderId), style: nameStyle),
        if (!mine && senderTitle != null) ...[
          const SizedBox(width: 4),
          MemberTitleBadge(title: senderTitle!),
        ],
      ];
      final messageColumn = Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: headerChildren,
          ),
          const SizedBox(height: kGroupNameBubbleGap),
          bubbleWithStatus,
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
                _unreadMarkerDot(scheme),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mine) const Spacer(),
            if (!mine) ...[
              _unreadMarkerDot(scheme),
              avatarFor(
                msg.senderId,
                onTap: onPeerTap != null
                    ? () => onPeerTap!(msg.senderId)
                    : null,
              ),
              const SizedBox(width: 6),
            ],
            bubbleWithStatus,
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
