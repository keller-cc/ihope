import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../utils/media_retry_callback.dart';
import 'chat_message_tile.dart';
import 'chat_scroll_coordinator.dart';

class ChatMessageListView extends StatefulWidget {
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
    this.announcementReadIds = const {},
    this.onAnnouncementTap,
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
  final MediaRetryCallback onMediaRetry;
  final void Function(ChatMessage msg) onSendRetry;
  final Future<void> Function() onRefresh;
  final Set<String> announcementReadIds;
  final void Function(ChatMessage msg)? onAnnouncementTap;

  @override
  State<ChatMessageListView> createState() => _ChatMessageListViewState();
}

class _ChatMessageListViewState extends State<ChatMessageListView> {
  int? _dividerIndex;
  String? _focusedMessageId;

  @override
  void initState() {
    super.initState();
    _dividerIndex = widget.scrollCoord.unreadDividerIndex;
    _focusedMessageId = widget.scrollCoord.focusedMessageId;
    widget.scrollCoord.addListener(_onScrollCoordVisualChanged);
  }

  @override
  void didUpdateWidget(ChatMessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollCoord != widget.scrollCoord) {
      oldWidget.scrollCoord.removeListener(_onScrollCoordVisualChanged);
      widget.scrollCoord.addListener(_onScrollCoordVisualChanged);
      _dividerIndex = widget.scrollCoord.unreadDividerIndex;
      _focusedMessageId = widget.scrollCoord.focusedMessageId;
    }
  }

  @override
  void dispose() {
    widget.scrollCoord.removeListener(_onScrollCoordVisualChanged);
    super.dispose();
  }

  /// 仅未读分割线与高亮定位变化时重建列表，避免滚动芯片状态触发整表刷新。
  void _onScrollCoordVisualChanged() {
    final divider = widget.scrollCoord.unreadDividerIndex;
    final focus = widget.scrollCoord.focusedMessageId;
    if (divider == _dividerIndex && focus == _focusedMessageId) return;
    setState(() {
      _dividerIndex = divider;
      _focusedMessageId = focus;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return const Center(child: CircularProgressIndicator());
    if (widget.error != null) return Center(child: Text(widget.error!));

    if (widget.messages.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
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
                        widget.isArchived
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

    final dividerIndex = _dividerIndex;
    final focusedId = _focusedMessageId;
    final scrollCoord = widget.scrollCoord;
    final messages = widget.messages;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) {
          scrollCoord.onScrollIdle();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: CustomScrollView(
          reverse: true,
          controller: widget.scrollController,
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
                        me: widget.me,
                        conversation: widget.conversation,
                        isGroup: widget.isGroup,
                        showUnreadDivider: dividerIndex == msgIndex,
                        focused: focusedId == msg.id,
                        nameFor: widget.nameFor,
                        avatarUrlFor: widget.avatarUrlFor,
                        onPeerTap: widget.onPeerTap,
                        onMediaRetry: widget.onMediaRetry,
                        onSendRetry: widget.onSendRetry,
                        announcementReadIds: widget.announcementReadIds,
                        onAnnouncementTap: widget.onAnnouncementTap,
                        allMessages: messages,
                        itemKey: scrollCoord.keyForMessage(msg.id),
                      ),
                    );
                  },
                  childCount: messages.length,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final msgIndex =
                        messages.indexWhere((m) => m.id == key.value);
                    if (msgIndex < 0) return null;
                    return messages.length - 1 - msgIndex;
                  },
                ),
              ),
            ),
            const SliverFillRemaining(hasScrollBody: false, child: SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
