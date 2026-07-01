import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/message.dart';

/// 聊天列表滚动、未读气泡、定位高亮（私聊/群聊共用）。
class ChatScrollCoordinator {
  ChatScrollCoordinator({
    required this.scrollController,
    required this.onChanged,
    required this.isMounted,
    required this.onReachedBottom,
    required this.firstUnreadIndexIn,
  });

  final ScrollController scrollController;
  final VoidCallback onChanged;
  final bool Function() isMounted;
  final VoidCallback onReachedBottom;
  final int? Function(List<ChatMessage> messages, DateTime? readAt)
      firstUnreadIndexIn;

  bool tailPinned = true;
  int belowUnreadCount = 0;
  int enterUnreadCount = 0;
  bool showJumpToBottom = false;
  bool showJumpToUnread = false;
  int? unreadDividerAtIndex;
  DateTime? readAtSnapshot;

  String? focusedMessageId;
  Timer? _focusTimer;
  bool _suppressScrollHandling = false;
  final _messageItemKeys = <String, GlobalKey>{};

  static const _bottomThreshold = 96.0;

  void attach() => scrollController.addListener(_onScroll);
  void detach() {
    scrollController.removeListener(_onScroll);
    _focusTimer?.cancel();
  }

  double get _stickThreshold {
    if (!scrollController.hasClients) return 120;
    final v = scrollController.position.viewportDimension;
    return math.max(120, v * 0.35);
  }

  bool get isAtBottom {
    if (!scrollController.hasClients) return true;
    return scrollController.position.pixels <= _bottomThreshold;
  }

  bool get isNearBottom {
    if (!scrollController.hasClients) return true;
    return scrollController.position.pixels <= _stickThreshold;
  }

  GlobalKey keyForMessage(String id) =>
      _messageItemKeys.putIfAbsent(id, GlobalKey.new);

  void applyReadSnapshot({required DateTime? readAt, required int unread}) {
    readAtSnapshot = readAt;
    enterUnreadCount = unread;
    showJumpToUnread = unread > 0;
    unreadDividerAtIndex = null;
    tailPinned = true;
  }

  void _onScroll() {
    if (_suppressScrollHandling) return;
    tailPinned = isNearBottom;
    if (!isNearBottom) return;

    if (belowUnreadCount > 0 || showJumpToBottom) {
      belowUnreadCount = 0;
      showJumpToBottom = false;
      onChanged();
    }
    if (isAtBottom) {
      _clearUnreadDivider();
      onReachedBottom();
    }
  }

  void _clearUnreadDivider() {
    if (unreadDividerAtIndex == null) return;
    unreadDividerAtIndex = null;
    onChanged();
  }

  void maybeMarkReadWithLast(ChatMessage last) {
    if (!tailPinned) return;
    if (enterUnreadCount > 0 && showJumpToUnread) return;
    readAtSnapshot = last.createdAt;
    enterUnreadCount = 0;
    showJumpToUnread = false;
    unreadDividerAtIndex = null;
    onChanged();
  }

  void onJumpToBottom(List<ChatMessage> messages, Future<void> Function() markRead) {
    tailPinned = true;
    belowUnreadCount = 0;
    showJumpToBottom = false;
    showJumpToUnread = false;
    onChanged();
    scrollToBottom(animated: true);
    if (messages.isNotEmpty) {
      final lastId = messages.last.id;
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (isMounted()) focusMessage(lastId);
      });
      unawaited(markRead());
    }
  }

  void onJumpToUnread(List<ChatMessage> messages) {
    final idx = firstUnreadIndexIn(messages, readAtSnapshot);
    if (idx == null) {
      showJumpToUnread = false;
      onChanged();
      return;
    }
    final msg = messages[idx];
    showJumpToUnread = false;
    unreadDividerAtIndex = idx;
    onChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(scrollToMessage(msg.id, viewportAlign: 0.68));
      focusMessage(msg.id);
    });
  }

  void handleTailAfterMessage({
    required bool atBottom,
    required bool fromPeer,
    required List<ChatMessage> messages,
    required Future<void> Function() markRead,
  }) {
    if (atBottom) {
      tailPinned = true;
      belowUnreadCount = 0;
      showJumpToBottom = false;
      unreadDividerAtIndex = null;
      onChanged();
      unawaited(markRead());
      return;
    }
    if (fromPeer) {
      belowUnreadCount++;
      showJumpToBottom = true;
      onChanged();
    }
  }

  void scrollToBottom({bool animated = false}) {
    void once() {
      if (!isMounted() || !scrollController.hasClients) return;
      final target = scrollController.position.minScrollExtent;
      _suppressScrollHandling = true;
      try {
        if (animated) {
          scrollController
              .animateTo(
                target,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() => _suppressScrollHandling = false);
        } else {
          scrollController.jumpTo(target);
          _suppressScrollHandling = false;
        }
      } catch (_) {
        _suppressScrollHandling = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => once());
  }

  void stickToTailIfPinned() {
    if (!scrollController.hasClients || !tailPinned) return;
    if (scrollController.position.pixels > 1) {
      _suppressScrollHandling = true;
      scrollController.jumpTo(scrollController.position.minScrollExtent);
      _suppressScrollHandling = false;
    }
  }

  void focusMessage(String messageId) {
    _focusTimer?.cancel();
    focusedMessageId = messageId;
    onChanged();
    _focusTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!isMounted()) return;
      focusedMessageId = null;
      onChanged();
    });
  }

  Future<void> scrollToMessage(
    String messageId, {
    double viewportAlign = 0.68,
    bool animated = true,
  }) async {
    void run({int attempt = 0}) {
      if (!isMounted() || attempt > 12) return;
      final ctx = _messageItemKeys[messageId]?.currentContext;
      if (ctx == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => run(attempt: attempt + 1));
        return;
      }
      final target = ctx.findRenderObject();
      if (target == null || !scrollController.hasClients) return;
      final viewport = RenderAbstractViewport.of(target);
      final revealed = viewport.getOffsetToReveal(target, viewportAlign);
      final pos = scrollController.position;
      final offset =
          revealed.offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _suppressScrollHandling = true;
      if (animated) {
        pos
            .animateTo(
              offset,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _suppressScrollHandling = false);
      } else {
        pos.jumpTo(offset);
        _suppressScrollHandling = false;
      }
    }
    run();
  }
}
