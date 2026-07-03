import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/message.dart';

/// 聊天列表滚动、未读气泡、定位（私聊/群聊共用）。
class ChatScrollCoordinator {
  ChatScrollCoordinator({
    required this.scrollController,
    required this.onChanged,
    required this.isMounted,
    required this.onReachedBottom,
  });

  final ScrollController scrollController;
  final VoidCallback onChanged;
  final bool Function() isMounted;
  final VoidCallback onReachedBottom;

  bool tailPinned = true;
  int belowUnreadCount = 0;
  int enterUnreadCount = 0;
  bool showJumpToBottom = false;
  bool showJumpToUnread = false;
  bool showScrollToLatestArrow = false;
  double scrollToLatestArrowOpacity = 0;
  DateTime? readAtSnapshot;

  static const enterUnreadDividerThreshold = 10;

  /// 反向列表：0=视口底部，1=视口顶部；未读定位在上方留白区。
  static const unreadJumpViewportAlign = 0.80;

  /// 进入会话时的未读 id（不含之后离开底部收到的新消息）。
  final Set<String> _enterUnreadIds = {};
  final Set<String> _sessionSeenEnterUnreadIds = {};

  /// 离开底部期间收到的新消息 id。
  final List<String> _tailNewMessageIds = [];
  final Set<String> _sessionSeenTailNewIds = {};

  String? _enterDividerMessageId;
  int _sessionEnterUnreadTotal = 0;
  bool _unreadSessionActive = false;

  String? focusedMessageId;
  Timer? _focusTimer;
  Timer? _arrowFadeTimer;
  Timer? _arrowHoldTimer;
  bool _suppressScrollHandling = false;
  final _messageItemKeys = <String, GlobalKey>{};

  List<ChatMessage> _threadMessages = const [];
  String? _meId;
  bool _enterUnreadIdsInitialized = false;

  double _lastScrollPixels = 0;
  DateTime _lastScrollTime = DateTime.now();

  static const _bottomThreshold = 96.0;
  static const _estimatedItemExtent = 72.0;
  static const _fastScrollVelocity = 600.0;
  static const _arrowIdleHold = Duration(milliseconds: 1200);
  static const _arrowFadeTick = Duration(milliseconds: 50);
  static const _arrowFadeStep = 0.025;

  void attach() {
    scrollController.addListener(_onScroll);
    if (scrollController.hasClients) {
      _lastScrollPixels = scrollController.position.pixels;
    }
  }

  void detach() {
    scrollController.removeListener(_onScroll);
    _focusTimer?.cancel();
    _cancelArrowTimers();
    _unreadSessionActive = false;
  }

  /// 每次进入聊天页只初始化一次，避免二次加载重置未读进度。
  void beginUnreadSession({required DateTime? readAt, required int unread}) {
    if (_unreadSessionActive) return;
    _unreadSessionActive = true;
    applyReadSnapshot(readAt: readAt, unread: unread);
  }

  void bindThread(List<ChatMessage> messages, String meId) {
    _threadMessages = messages;
    _meId = meId;
    _ensureEnterUnreadIds();
  }

  int? get unreadDividerIndex {
    final id = _enterDividerMessageId;
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
    showJumpToUnread = false;
    _syncEnterDividerIfNeeded();
  }

  bool _hasOffscreenEnterUnread() {
    for (final id in _enterUnreadIds) {
      if (_sessionSeenEnterUnreadIds.contains(id)) continue;
      if (!_isMessageVisibleInViewport(id)) return true;
    }
    return false;
  }

  void _markVisibleEnterUnreadSeen() {
    for (final id in _enterUnreadIds) {
      if (_sessionSeenEnterUnreadIds.contains(id)) continue;
      if (_isMessageVisibleInViewport(id)) {
        _sessionSeenEnterUnreadIds.add(id);
      }
    }
  }

  /// 布局完成后同步未读气泡：仅当仍有未读在视口外时显示。
  void syncEnterUnreadBubbleAfterLayout() {
    if (_meId == null || _threadMessages.isEmpty) return;

    final seenBefore = _sessionSeenEnterUnreadIds.length;
    _markVisibleEnterUnreadSeen();

    final prevEnter = enterUnreadCount;
    final prevShowEnter = showJumpToUnread;
    enterUnreadCount = _countEnterUnreadRemaining();
    showJumpToUnread = _hasOffscreenEnterUnread();

    if (prevEnter != enterUnreadCount ||
        prevShowEnter != showJumpToUnread ||
        _sessionSeenEnterUnreadIds.length != seenBefore) {
      onChanged();
    }

    if (enterUnreadCount == 0 && isNearBottom) {
      onReachedBottom();
    }
  }

  void _syncEnterDividerIfNeeded() {
    if (_enterDividerMessageId != null ||
        _sessionEnterUnreadTotal <= enterUnreadDividerThreshold) {
      return;
    }
    final first = _firstEnterUnreadId;
    if (first == null) return;
    _enterDividerMessageId = first;
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
    _sessionEnterUnreadTotal = unread;
    enterUnreadCount = unread;
    showJumpToUnread = false;
    tailPinned = true;
    _sessionSeenEnterUnreadIds.clear();
    _sessionSeenTailNewIds.clear();
    _enterUnreadIds.clear();
    _tailNewMessageIds.clear();
    _enterUnreadIdsInitialized = false;
    _enterDividerMessageId = null;
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

  bool _isMessageVisibleInViewport(String messageId) {
    final ctx = _messageItemKeys[messageId]?.currentContext;
    if (ctx == null) return false;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !scrollController.hasClients) {
      return false;
    }
    final scrollable = Scrollable.maybeOf(ctx);
    if (scrollable == null) return false;
    final viewportBox = scrollable.context.findRenderObject();
    if (viewportBox is! RenderBox || !viewportBox.hasSize) return false;

    final top = box.localToGlobal(Offset.zero, ancestor: viewportBox).dy;
    final bottom = top + box.size.height;
    final viewportHeight = viewportBox.size.height;
    return bottom > 0 && top < viewportHeight;
  }

  void _markEnterUnreadSeenInViewport({required bool scrollingUp}) {
    if (!scrollingUp) return;
    for (final id in _enterUnreadIds) {
      if (_sessionSeenEnterUnreadIds.contains(id)) continue;
      if (_isMessageVisibleInViewport(id)) {
        _sessionSeenEnterUnreadIds.add(id);
      }
    }
  }

  void _markTailNewSeenInViewport() {
    for (final id in _tailNewMessageIds) {
      if (_sessionSeenTailNewIds.contains(id)) continue;
      if (_isMessageVisibleInViewport(id)) {
        _sessionSeenTailNewIds.add(id);
      }
    }
  }

  void updateUnreadVisibility({bool scrollingUp = false}) {
    if (_meId == null || _threadMessages.isEmpty) return;

    final seenBefore = _sessionSeenEnterUnreadIds.length;
    _markEnterUnreadSeenInViewport(scrollingUp: scrollingUp);

    final prevEnter = enterUnreadCount;
    final prevShowEnter = showJumpToUnread;
    enterUnreadCount = _countEnterUnreadRemaining();
    showJumpToUnread = _hasOffscreenEnterUnread();

    if (prevEnter != enterUnreadCount ||
        prevShowEnter != showJumpToUnread ||
        _sessionSeenEnterUnreadIds.length != seenBefore) {
      onChanged();
    }
  }

  void _updateTailNewBubble({required bool scrollingDown}) {
    final seenBefore = _sessionSeenTailNewIds.length;
    if (scrollingDown) _markTailNewSeenInViewport();

    final prevCount = belowUnreadCount;
    final prevShow = showJumpToBottom;
    belowUnreadCount = _countTailNewRemaining();
    showJumpToBottom = belowUnreadCount > 0 && !isAtBottom;

    if (prevCount != belowUnreadCount ||
        prevShow != showJumpToBottom ||
        _sessionSeenTailNewIds.length != seenBefore) {
      onChanged();
    }
  }

  void _updateScrollArrow({required bool scrollingDown, required double velocity}) {
    final prevOpacity = scrollToLatestArrowOpacity;
    final prevShow = showScrollToLatestArrow;

    if (isAtBottom) {
      _cancelArrowTimers();
      scrollToLatestArrowOpacity = 0;
      showScrollToLatestArrow = false;
    } else if (scrollingDown) {
      _cancelArrowTimers();
      scrollToLatestArrowOpacity = 1;
      showScrollToLatestArrow = true;
    } else if (showScrollToLatestArrow) {
      final slowRatio = velocity < _fastScrollVelocity
          ? (1 - velocity / _fastScrollVelocity).clamp(0.0, 1.0)
          : 0.0;
      scrollToLatestArrowOpacity = math.max(
        0,
        scrollToLatestArrowOpacity - (_arrowFadeStep * (0.5 + slowRatio)),
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
    _arrowHoldTimer?.cancel();
    _arrowHoldTimer = Timer(_arrowIdleHold, () {
      if (!isMounted() || isAtBottom || !showScrollToLatestArrow) return;
      _startArrowFadeOut();
    });
  }

  void _startArrowFadeOut() {
    _arrowFadeTimer?.cancel();
    _arrowFadeTimer = Timer.periodic(_arrowFadeTick, (timer) {
      if (!isMounted()) {
        timer.cancel();
        return;
      }
      if (isAtBottom) {
        _cancelArrowTimers();
        scrollToLatestArrowOpacity = 0;
        showScrollToLatestArrow = false;
        onChanged();
        return;
      }
      scrollToLatestArrowOpacity =
          math.max(0, scrollToLatestArrowOpacity - _arrowFadeStep);
      if (scrollToLatestArrowOpacity < 0.02) {
        scrollToLatestArrowOpacity = 0;
        showScrollToLatestArrow = false;
        timer.cancel();
        _arrowFadeTimer = null;
      }
      onChanged();
    });
  }

  void _cancelArrowTimers() {
    _arrowHoldTimer?.cancel();
    _arrowHoldTimer = null;
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
    final scrollingUp = delta > 0.5;
    final scrollingDown = delta < -0.5;
    _lastScrollPixels = pos.pixels;
    _lastScrollTime = now;

    tailPinned = isNearBottom;
    updateUnreadVisibility(scrollingUp: scrollingUp);
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
      _cancelArrowTimers();
      showScrollToLatestArrow = false;
      scrollToLatestArrowOpacity = 0;
      onReachedBottom();
    }
  }

  void maybeMarkReadWithLast(ChatMessage last) {
    if (!tailPinned || showJumpToUnread) return;
    readAtSnapshot = last.createdAt;
    enterUnreadCount = 0;
    showJumpToUnread = false;
    _sessionSeenEnterUnreadIds.addAll(_enterUnreadIds);
    _sessionSeenTailNewIds.addAll(_tailNewMessageIds);
    onChanged();
  }

  void onJumpToNewMessages(List<ChatMessage> messages) {
    final id = _firstTailNewId;
    _tailNewMessageIds.clear();
    _sessionSeenTailNewIds.clear();
    belowUnreadCount = 0;
    showJumpToBottom = false;
    onChanged();
    if (id != null) {
      _jumpToMessageId(id, messages, highlight: true, viewportAlign: 0.38);
    }
  }

  void onJumpToUnread(List<ChatMessage> messages) {
    final id = _firstEnterUnreadId;
    if (id == null) return;
    _jumpToMessageId(
      id,
      messages,
      highlight: true,
      viewportAlign: unreadJumpViewportAlign,
    );
  }

  void onJumpToLatest(List<ChatMessage> messages) {
    _cancelArrowTimers();
    showScrollToLatestArrow = false;
    scrollToLatestArrowOpacity = 0;
    onChanged();
    tailPinned = true;
    scrollToBottom(animated: true);
  }

  void _jumpToMessageId(
    String messageId,
    List<ChatMessage> messages, {
    required bool highlight,
    double viewportAlign = 0.42,
  }) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scrollTowardMessageIndex(idx, messages.length);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await scrollToMessage(messageId, viewportAlign: viewportAlign);
      if (highlight) focusMessage(messageId);
      syncEnterUnreadBubbleAfterLayout();
      _updateTailNewBubble(scrollingDown: true);
    });
  }

  void focusMessage(String messageId) {
    _focusTimer?.cancel();
    focusedMessageId = messageId;
    onChanged();
    _focusTimer = Timer(const Duration(milliseconds: 1300), () {
      if (!isMounted()) return;
      focusedMessageId = null;
      onChanged();
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
                syncEnterUnreadBubbleAfterLayout();
                _updateTailNewBubble(scrollingDown: true);
              });
        } else {
          scrollController.jumpTo(target);
          _suppressScrollHandling = false;
          syncEnterUnreadBubbleAfterLayout();
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
    _sessionSeenEnterUnreadIds.add(messageId);
  }

  @visibleForTesting
  void addTailNewMessageForTest(String messageId) {
    _tailNewMessageIds.add(messageId);
    belowUnreadCount = _countTailNewRemaining();
    showJumpToBottom = belowUnreadCount > 0;
  }

  @visibleForTesting
  Set<String> get enterUnreadIds => Set.unmodifiable(_enterUnreadIds);
}
