import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../widgets/chat_scroll_chip.dart';
import 'chat_scroll_coordinator.dart';

/// 右侧浮动条：上方「未读消息」，下方「新消息」；底部居中为快速下滑时的「回最新」箭头。
class ChatFloatingChips extends StatelessWidget {
  const ChatFloatingChips({
    super.key,
    required this.scrollCoord,
    required this.messages,
  });

  final ChatScrollCoordinator scrollCoord;
  final List<ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scrollCoord,
      builder: (context, _) => _ChatFloatingChipsBody(
        scrollCoord: scrollCoord,
        messages: messages,
      ),
    );
  }
}

class _ChatFloatingChipsBody extends StatelessWidget {
  const _ChatFloatingChipsBody({
    required this.scrollCoord,
    required this.messages,
  });

  final ChatScrollCoordinator scrollCoord;
  final List<ChatMessage> messages;

  static const unreadChipTopFactor = 0.12;
  static const newMessageChipBottomFactor = 0.14;
  static const scrollArrowBottomFactor = 0.02;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showJumpToUnread = scrollCoord.showJumpToUnread;
    final showJumpToBottom = scrollCoord.showJumpToBottom;
    final showScrollToLatestArrow = scrollCoord.showScrollToLatestArrow;
    final scrollToLatestArrowOpacity = scrollCoord.scrollToLatestArrowOpacity;
    final enterUnreadCount = scrollCoord.enterUnreadCount;
    final belowUnreadCount = scrollCoord.belowUnreadCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        final unreadTop = h * unreadChipTopFactor;
        final newMessageBottom = h * newMessageChipBottomFactor;
        final arrowBottom = h * scrollArrowBottomFactor;

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
                  onTap: () => scrollCoord.onJumpToUnread(messages),
                ),
              ),
            if (showJumpToBottom)
              Positioned(
                right: 0,
                bottom: newMessageBottom,
                child: ChatScrollChip(
                  label: belowUnreadCount > 0
                      ? '$belowUnreadCount条新消息'
                      : '新消息',
                  icon: Icons.south_rounded,
                  onTap: () => scrollCoord.onJumpToNewMessages(messages),
                ),
              ),
            if (showScrollToLatestArrow && scrollToLatestArrowOpacity > 0.01)
              Positioned(
                left: 0,
                right: 0,
                bottom: arrowBottom,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: scrollToLatestArrowOpacity.clamp(0.0, 1.0),
                    duration: const Duration(milliseconds: 80),
                    child: Material(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
                      elevation: 2,
                      shadowColor: Colors.black26,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => scrollCoord.onJumpToLatest(messages),
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
      },
    );
  }
}
