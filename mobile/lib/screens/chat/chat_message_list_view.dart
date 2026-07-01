import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import 'chat_message_tile.dart';
import 'chat_scroll_coordinator.dart';

class ChatMessageListView extends StatelessWidget {
  const ChatMessageListView({
    super.key,
    required this.loading,
    required this.error,
    required this.messages,
    required this.conversation,
    required this.isGroup,
    required this.isArchived,
    required this.scrollController,
    required this.scrollCoord,
    required this.me,
    required this.nameFor,
    required this.avatarUrlFor,
    required this.onPeerTap,
    required this.onMediaRetry,
    required this.onSendRetry,
    required this.onRefresh,
  });

  final bool loading;
  final String? error;
  final List<ChatMessage> messages;
  final ConversationItem conversation;
  final bool isGroup;
  final bool isArchived;
  final ScrollController scrollController;
  final ChatScrollCoordinator scrollCoord;
  final User me;
  final String Function(String userId) nameFor;
  final String? Function(String userId) avatarUrlFor;
  final void Function(String userId) onPeerTap;
  final Future<void> Function(String messageId) onMediaRetry;
  final void Function(ChatMessage msg) onSendRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return Center(child: Text(error!));

    if (messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text('暂无消息', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        isArchived
                            ? '此会话暂无历史消息'
                            : '下拉刷新 · 下方输入发送第一条消息',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final dividerIndex = scrollCoord.unreadDividerAtIndex;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        reverse: true,
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final msgIndex = messages.length - 1 - index;
                  final msg = messages[msgIndex];
                  return KeyedSubtree(
                    key: ValueKey(msg.id),
                    child: ChatMessageTile(
                      msg: msg,
                      prev: msgIndex > 0 ? messages[msgIndex - 1] : null,
                      me: me,
                      conversation: conversation,
                      isGroup: isGroup,
                      showUnreadDivider: dividerIndex == msgIndex,
                      focused: scrollCoord.focusedMessageId == msg.id,
                      nameFor: nameFor,
                      avatarUrlFor: avatarUrlFor,
                      onPeerTap: onPeerTap,
                      onMediaRetry: onMediaRetry,
                      onSendRetry: onSendRetry,
                      itemKey: scrollCoord.keyForMessage(msg.id),
                    ),
                  );
                },
                childCount: messages.length,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  final msgIndex = messages.indexWhere((m) => m.id == key.value);
                  if (msgIndex < 0) return null;
                  return messages.length - 1 - msgIndex;
                },
              ),
            ),
          ),
          const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
        ],
      ),
    );
  }
}
