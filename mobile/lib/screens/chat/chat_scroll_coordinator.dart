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
  bool showScrollToLatestArrow = false;
  double scrollToLatestArrowOpacity = 0;
  DateTime? readAtSnapshot;

  /// 进入会话时的未读消息 id（不含之后滑走期间收到的新消息）。
  final Set<String> _enterUnreadIds = {};
  final Set<String> _sessionSeenEnterUnreadIds = {};

  /// 离开底部期间收到的新消息 id（按到达顺序）。
  final List<String> _tailNewMessageIds = [];
  final Set<String> _sessionSeenTailNewIds = {};

  /// 本次进入会话后，已在视口内出现过的未读消息 id（红点用，只增不减）。
  final Set<String> _sessionSeenUnreadIds = {};

  /// 进入会话未读块的分割线（进入时有未读即固定，不随 tail 新消息变化）。
  String? _enterDividerMessageId;
  /// 仅 tail 新消息块的分割线（点击「新消息」跳转时显示）。
  String? _tailDividerMessageId;

  String? focusedMessageId;
  Timer? _focusTimer;
  bool _suppressScrollHandling = false;
  Timer? _arrowFadeTimer;
  final _messageItemKeys = <String, GlobalKey>{};

  List<ChatMessage> _threadMessages = const [];
  String? _meId;
  bool _enterUnreadIdsInitialized = false;

  double _lastScrollPixels = 0;
  DateTime _lastScrollTime = DateTime.now();

  static const _bottomThreshold = 96.0;
  static const _estimatedItemExtent = 72.0;
  static const _fastScrollVelocity = 900.0;

  void attach() {
    scrollController.addListener(_onScroll);
    if (scrollController.hasClients) {
      _lastScrollPixels = scrollController.position.pixels;
    }
  }

  void detach() {
    scrollController.removeListener(_onScroll);
    _focusTimer?.cancel();
    _arrowFadeTimer?.cancel();
  }

  void bindThread(List<ChatMessage> messages, String meId) {
    _threadMessages = messages;
    _meId = meId;
    _ensureEnterUnreadIds();
  }

  int? get unreadDividerIndex {
    final id = _enterDividerMessageId ?? _tailDividerMessageId;
    if (id == null) return null;
    final idx = _threadMessages.indexWhere((m) => m.id == id);
    return idx >= 0 ? idx : null;
  }

  void _ensureEnterUnreadIds() {
    if (_enterUnreadIdsInitialized) return;
    _enterUnreadIdsInitialized = true;
    final meId = _meId;
    if (meId == null) return;
    for (final m in _threadMessages) {
      if (isPeerUnread(m, meId, readAtSnapshot)) {
        _enterUnreadIds.add(m.id);
      }
    }
    enterUnreadCount = _countEnterUnreadRemaining();
    showJumpToUnread = enterUnreadCount > 0;
    _syncEnterDivider();
  }

  /// 进入会话且存在未读时，在第一条进入未读处显示分割线（一次性锚定）。
  void _syncEnterDivider() {
    if (_enterDividerMessageId != null || _enterUnreadIds.isEmpty) return;
    final first = _firstEnterUnreadId;
    if (first == null) return;
    _enterDividerMessageId = first;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isMounted()) onChanged();
    });
  }

  void _clearUnreadDivider() {
    if (_enterDividerMessageId == null && _tailDividerMessageId == null) return;
    _enterDividerMessageId = null;
    _tailDividerMessageId = null;
    onChanged();
  }

  void _clearTailDivider() {
    if (_tailDividerMessageId == null) return;
    _tailDividerMessageId = null;
    onChanged();
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
    tailPinned = true;
    _sessionSeenUnreadIds.clear();
    _sessionSeenEnterUnreadIds.clear();
    _sessionSeenTailNewIds.clear();
    _enterUnreadIds.clear();
    _tailNewMessageIds.clear();
    _enterUnreadIdsInitialized = false;
    _enterDividerMessageId = null;
    _tailDividerMessageId = null;
    belowUnreadCount = 0;
    showJumpToBottom = false;
    showScrollToLatestArrow = false;
    scrollToLatestArrowOpacity = 0;
  }

  static bool isPeerUnread(ChatMessage m, String meId, DateTime? readAt) {
    if (m.senderId == meId) return false;
    if (m.type == 'announcement' || m.type == 'system') return false;
    return readAt == null || m.createdAt.isAfter(readAt);
  }

  bool isUnmarkedPeerUnread(ChatMessage m) {
    if (_enterUnreadIds.contains(m.id) &&
        !_sessionSeenEnterUnreadIds.contains(m.id)) {
      return true;
    }
    if (_tailNewMessageIds.contains(m.id) &&
        !_sessionSeenTailNewIds.contains(m.id)) {
      return true;
    }
    return false;
  }

  int? get firstUnmarkedUnreadIndex {
    final meId = _meId;
    if (meId == null) return null;
    for (var i = 0; i < _threadMessages.length; i++) {
      if (isUnmarkedPeerUnread(_threadMessages[i])) return i;
    }
    return null;
  }

  String? get _firstEnterUnreadId {
    for (final m in _threadMessages) {
      if (_enterUnreadIds.contains(m.id)) return m.id;
    }
    return null;
  }

  String? get _firstTailNewId {
    for (final id in _tailNewMessageIds) {
      if (!_sessionSeenTailNewIds.contains(id)) return id;
    }
    return null;
  }

  int _countEnterUnreadRemaining() {
    var n = 0;
    for (final id in _enterUnreadIds) {
      if (!_sessionSeenEnterUnreadIds.contains(id)) n++;
    }
    return n;
  }

  int _countTailNewRemaining() {
    var n = 0;
    for (final id in _tailNewMessageIds) {
      if (!_sessionSeenTailNewIds.contains(id)) n++;
    }
    return n;
  }

  double? _messageViewportTop(String messageId) {
    final ctx = _messageItemKeys[messageId]?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !scrollController.hasClients) {
      return null;
    }
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable == null) return null;
    final viewportBox = scrollable.context.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.hasSize) return null;

    return box.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
  }

  bool _isMessageVisibleInViewport(String messageId) {
    final top = _messageViewportTop(messageId);
    if (top == null) return false;
    final ctx = _messageItemKeys[messageId]?.currentContext;
    if (ctx == null) return false;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable == null) return false;
    final viewportBox = scrollable.context.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.hasSize) return false;

    final bottom = top + box.size.height;
    final viewportHeight = viewportBox.size.height;
    return bottom > 0 && top < viewportHeight;
  }

  void _markEnterUnreadSeenInViewport() {
    for (final id in _enterUnreadIds) {
      if (_sessionSeenEnterUnreadIds.contains(id)) continue;
      if (_isMessageVisibleInViewport(id)) {
        _sessionSeenEnterUnreadIds.add(id);
        _sessionSeenUnreadIds.add(id);
      }
    }
  }

  void _markTailNewSeenInViewport() {
    for (final id in _tailNewMessageIds) {
      if (_sessionSeenTailNewIds.contains(id)) continue;
      if (_isMessageVisibleInViewport(id)) {
        _sessionSeenTailNewIds.add(id);
        _sessionSeenUnreadIds.add(id);
      }
    }
  }

  void _markAllPeerUnreadSeen() {
    _sessionSeenEnterUnreadIds.addAll(_enterUnreadIds);
    _sessionSeenTailNewIds.addAll(_tailNewMessageIds);
    _sessionSeenUnreadIds.addAll(_enterUnreadIds);
    _sessionSeenUnreadIds.addAll(_tailNewMessageIds);
  }

  bool _hasReachedEnterUnreadBoundary() {
    final id = _firstEnterUnreadId;
    if (id == null) return true;
    return _isMessageVisibleInViewport(id);
  }

  void updateUnreadVisibility() {
    if (_meId == null || _threadMessages.isEmpty) return;

    _markEnterUnreadSeenInViewport();

    final prevEnter = enterUnreadCount;
    final prevShowEnter = showJumpToUnread;
    enterUnreadCount = _countEnterUnreadRemaining();
    showJumpToUnread =
        enterUnreadCount > 0 && !_hasReachedEnterUnreadBoundary();

    if (prevEnter != enterUnreadCount || prevShowEnter != showJumpToUnread) {
      onChanged();
    }
  }

  void _updateTailNewBubble({required bool scrollingDown}) {
    if (scrollingDown) {
      _markTailNewSeenInViewport();
    }

    final prevCount = belowUnreadCount;
    final prevShow = showJumpToBottom;
    belowUnreadCount = _countTailNewRemaining();
    showJumpToBottom = belowUnreadCount > 0 && !isAtBottom;

    if (prevCount != belowUnreadCount || prevShow != showJumpToBottom) {
      onChanged();
    }
  }

  void _updateScrollArrow({required bool scrollingDown, required double velocity}) {
    final prevOpacity = scrollToLatestArrowOpacity;
    final prevShow = showScrollToLatestArrow;

    if (isAtBottom) {
      _cancelArrowFadeTimer();
      scrollToLatestArrowOpacity = 0;
      showScrollToLatestArrow = false;
    } else if (scrollingDown && velocity >= _fastScrollVelocity) {
      _cancelArrowFadeTimer();
      scrollToLatestArrowOpacity = 1;
      showScrollToLatestArrow = true;
    } else if (showScrollToLatestArrow && scrollingDown) {
      final slowRatio = (1 - (velocity / _fastScrollVelocity)).clamp(0.0, 1.0);
      scrollToLatestArrowOpacity = math.max(
        0,
        scrollToLatestArrowOpacity - (0.06 + slowRatio * 0.14),
      );
      if (scrollToLatestArrowOpacity < 0.02) {
        scrollToLatestArrowOpacity = 0;
        showScrollToLatestArrow = false;
      }
    }

    if (prevOpacity != scrollToLatestArrowOpacity ||
        prevShow != showScrollToLatestArrow) {
      onChanged();
    }
  }

  void onScrollIdle() {
    if (!showScrollToLatestArrow || isAtBottom) return;
    _scheduleArrowFadeOut();
  }

  void _scheduleArrowFadeOut() {
    _arrowFadeTimer?.cancel();
    _arrowFadeTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!isMounted()) {
        timer.cancel();
        return;
      }
      if (isAtBottom) {
        _cancelArrowFadeTimer();
        scrollToLatestArrowOpacity = 0;
        showScrollToLatestArrow = false;
        onChanged();
        return;
      }
      scrollToLatestArrowOpacity = math.max(0, scrollToLatestArrowOpacity - 0.07);
      if (scrollToLatestArrowOpacity < 0.02) {
        scrollToLatestArrowOpacity = 0;
        showScrollToLatestArrow = false;
        timer.cancel();
        _arrowFadeTimer = null;
      }
      onChanged();
    });
  }

  void _cancelArrowFadeTimer() {
    _arrowFadeTimer?.cancel();
    _arrowFadeTimer = null;
  }

  void _onScroll() {
    if (_suppressScrollHandling) return;

    final pos = scrollController.position;
    final now = DateTime.now();
    final dtMs = now.difference(_lastScrollTime).inMilliseconds.clamp(1, 500);
    final delta = pos.pixels - _lastScrollPixels;
    final velocity = delta.abs() / dtMs * 1000;
    final scrollingDown = delta < -0.5;
    _lastScrollPixels = pos.pixels;
    _lastScrollTime = now;

    tailPinned = isNearBottom;
    updateUnreadVisibility();
    _updateTailNewBubble(scrollingDown: scrollingDown);
    _updateScrollArrow(scrollingDown: scrollingDown, velocity: velocity);

    if (!isNearBottom) return;

    if (isAtBottom) {
      if (belowUnreadCount > 0 || showJumpToBottom) {
        _tailNewMessageIds.clear();
        _sessionSeenTailNewIds.clear();
        belowUnreadCount = 0;
        showJumpToBottom = false;
        onChanged();
      }
      _clearTailDivider();
      showScrollToLatestArrow = false;
      scrollToLatestArrowOpacity = 0;
      onReachedBottom();
    }
  }

  void maybeMarkReadWithLast(ChatMessage last) {
    if (!tailPinned) return;
    if (showJumpToUnread) return;
    readAtSnapshot = last.createdAt;
    enterUnreadCount = 0;
    showJumpToUnread = false;
    _markAllPeerUnreadSeen();
    _clearUnreadDivider();
    onChanged();
  }

  void onJumpToNewMessages(List<ChatMessage> messages) {
    final id = _firstTailNewId;
    if (id != null && _enterDividerMessageId == null) {
      _tailDividerMessageId = id;
    }
    _tailNewMessageIds.clear();
    _sessionSeenTailNewIds.clear();
    belowUnreadCount = 0;
    showJumpToBottom = false;
    onChanged();
    if (id == null) return;
    _jumpToMessageId(id, messages);
  }

  void onJumpToUnread(List<ChatMessage> messages) {
    final id = _firstEnterUnreadId;
    showJumpToUnread = false;
    onChanged();
    if (id == null) return;
    _sessionSeenEnterUnreadIds.add(id);
    _jumpToMessageId(id, messages);
    updateUnreadVisibility();
  }

  void onJumpToLatest(List<ChatMessage> messages) {
    _cancelArrowFadeTimer();
    showScrollToLatestArrow = false;
    scrollToLatestArrowOpacity = 0;
    onChanged();
    tailPinned = true;
    scrollToBottom(animated: true);
    if (messages.isNotEmpty) {
      final lastId = messages.last.id;
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (isMounted()) focusMessage(lastId);
      });
    }
  }

  void _jumpToMessageId(String messageId, List<ChatMessage> messages) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    onChanged();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollTowardMessageIndex(idx, messages.length);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await scrollToMessage(messageId, viewportAlign: 0.42);
      focusMessage(messageId);
      updateUnreadVisibility();
      _updateTailNewBubble(scrollingDown: true);
    });
  }

  void _scrollTowardMessageIndex(int msgIndex, int messageCount) {
    if (!scrollController.hasClients || messageCount <= 0) return;
    final pos = scrollController.position;
    final itemsFromBottom = messageCount - 1 - msgIndex;
    if (itemsFromBottom <= 0) {
      scrollController.jumpTo(pos.minScrollExtent);
      return;
    }
    final target = (itemsFromBottom * _estimatedItemExtent)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _suppressScrollHandling = true;
    scrollController.jumpTo(target);
    _suppressScrollHandling = false;
  }

  void handleTailAfterMessage({
    required bool atBottom,
    required bool fromPeer,
    required String messageId,
    required List<ChatMessage> messages,
    required Future<void> Function() markRead,
  }) {
    if (atBottom) {
      tailPinned = true;
      onChanged();
      unawaited(markRead());
      return;
    }
    if (fromPeer && !_tailNewMessageIds.contains(messageId)) {
      _tailNewMessageIds.add(messageId);
      belowUnreadCount = _countTailNewRemaining();
      showJumpToBottom = belowUnreadCount > 0;
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
              .whenComplete(() {
                _suppressScrollHandling = false;
                updateUnreadVisibility();
                _updateTailNewBubble(scrollingDown: true);
              });
        } else {
          scrollController.jumpTo(target);
          _suppressScrollHandling = false;
          updateUnreadVisibility();
          _updateTailNewBubble(scrollingDown: true);
        }
      } catch (_) {
        _suppressScrollHandling = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => once());
  }

  // TODO(scroll-lock): reverse 列表尾部插入仍会顶掉视口，待后续实现。
  void beginScrollLockForTailInsert() {}

  void endScrollLockAfterTailInsert() {}

  void stickToTailIfPinned() {
    if (!tailPinned) return;
    void once() {
      if (!scrollController.hasClients || !tailPinned) return;
      if (scrollController.position.pixels > 1) {
        _suppressScrollHandling = true;
        scrollController.jumpTo(scrollController.position.minScrollExtent);
        _suppressScrollHandling = false;
        updateUnreadVisibility();
        _updateTailNewBubble(scrollingDown: true);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => once());
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
    double viewportAlign = 0.42,
    bool animated = true,
  }) async {
    final completer = Completer<void>();
    void run({int attempt = 0}) {
      if (!isMounted()) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (attempt > 16) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final ctx = _messageItemKeys[messageId]?.currentContext;
      if (ctx == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => run(attempt: attempt + 1));
        return;
      }
      final target = ctx.findRenderObject();
      if (target == null || !scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) => run(attempt: attempt + 1));
        return;
      }
      final viewport = RenderAbstractViewport.of(target);
      final revealed = viewport.getOffsetToReveal(target, viewportAlign);
      final pos = scrollController.position;
      final offset =
          revealed.offset.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _suppressScrollHandling = true;
      void done() {
        _suppressScrollHandling = false;
        if (!completer.isCompleted) completer.complete();
      }

      if (animated) {
        pos.animateTo(
          offset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ).whenComplete(done);
      } else {
        pos.jumpTo(offset);
        done();
      }
    }

    run();
    return completer.future;
  }

  @visibleForTesting
  void markUnreadSeenInSession(String messageId) {
    _sessionSeenUnreadIds.add(messageId);
    _sessionSeenEnterUnreadIds.add(messageId);
  }

  @visibleForTesting
  Set<String> get sessionSeenUnreadIds => Set.unmodifiable(_sessionSeenUnreadIds);

  @visibleForTesting
  void addTailNewMessageForTest(String messageId) {
    _tailNewMessageIds.add(messageId);
    belowUnreadCount = _countTailNewRemaining();
    showJumpToBottom = belowUnreadCount > 0;
  }

  @visibleForTesting
  Set<String> get enterUnreadIds => Set.unmodifiable(_enterUnreadIds);
}
