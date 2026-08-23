import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/ws_service.dart';
import '../utils/announcement_read.dart';
import '../config/app_config.dart';
import '../utils/cloud_drive_launcher.dart';
import '../utils/media_payload.dart';
import '../utils/media_local_cache.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/app_page_route.dart';
import '../widgets/group_announcement_banner.dart';
import '../widgets/offline_banner.dart';
import '../widgets/voice_hint_toast.dart';
import 'announcement_detail_screen.dart';
import 'group_announcements_screen.dart';
import 'chat/chat_app_bar.dart';
import 'chat/chat_floating_chips.dart';
import 'chat/chat_message_list_view.dart';
import 'chat/chat_outgoing_controller.dart';
import 'chat/chat_scroll_coordinator.dart';
import 'chat/chat_thread_loader.dart';
import 'chat/large_file_send_choice.dart';
import 'chat_history/chat_history_jump.dart';
import 'chat_settings_screen.dart';
import 'group_manage_screen.dart';
import 'user_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.auth,
    required this.conversation,
    this.notification,
    this.initialUnreadCount = 0,
    this.initialFocusMessageId,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final NotificationService? notification;
  final int initialUnreadCount;
  final String? initialFocusMessageId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _subs = <StreamSubscription<dynamic>>[];

  late final ChatScrollCoordinator _scrollCoord;
  late final ChatThreadLoader _thread;
  late final ChatOutgoingController _outgoing;

  late ConversationItem _conversation;
  List<ChatMessage> _messages = [];
  final Set<String> _prefetchingImages = {};
  bool _loading = true;
  String? _error;
  int _historyEpoch = 0;
  Set<String> _announcementReadIds = {};
  final Set<String> _dismissedAnnouncementBannerIds = {};
  String? _pendingFocusMessageId;
  bool _popInProgress = false;

  bool get _isGroup => _conversation.type == 'group';

  bool get _announcementUnread => widget.auth.isAnnouncementUnread(
        _messages,
        readIds: _announcementReadIds,
      );

  List<ChatMessage> get _visibleUnreadAnnouncementBanners {
    final me = widget.auth.currentUser;
    if (me == null) return const [];
    // unreadList is newest-first; keep the 3 most recent, show oldest at top.
    final unread = AnnouncementRead.unreadList(
      _messages,
      readIds: _announcementReadIds,
      myUserId: me.id,
    ).where((a) => !_dismissedAnnouncementBannerIds.contains(a.id));
    return unread.take(3).toList(growable: false).reversed.toList(growable: false);
  }

  void _dismissAnnouncementBanner(String announcementId) {
    setState(() => _dismissedAnnouncementBannerIds.add(announcementId));
  }

  /// 从内存缓存同步灌入列表，首帧即可展示（返回首页再进不转圈）。
  void _hydrateFromMemoryCache() {
    final quick = ChatThreadLoader.quickMessagesFromMemory(
      widget.auth,
      _conversation,
    );
    if (quick == null) return;
    _messages = quick;
    _loading = false;
  }

  void _bindScrollToHydratedMessages() {
    if (_messages.isEmpty) return;
    final me = widget.auth.currentUser;
    if (me == null) return;
    _scrollCoord.bindThread(_messages, me.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _messages.isEmpty) return;
      _scrollCoord.stickToTailIfPinned();
    });
  }

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _pendingFocusMessageId = widget.initialFocusMessageId;
    _thread = ChatThreadLoader(auth: widget.auth, conversation: _conversation);
    _hydrateFromMemoryCache();

    _scrollCoord = ChatScrollCoordinator(
      scrollController: _scroll,
      isMounted: () => mounted,
      onReachedBottom: () => unawaited(_markReadToLast()),
    );
    _scrollCoord.attach();
    _bindScrollToHydratedMessages();

    _outgoing = ChatOutgoingController(
      auth: widget.auth,
      conversation: () => _conversation,
      onPending: _onMessagePending,
      onSent: _onMessageSent,
      onFailed: _onMessageFailed,
      onError: _showSnack,
      onLargeFilePrompt: _promptLargeFile,
    );

    widget.auth.setOpenConversation(_conversation.id);
    widget.notification?.onConversationOpened(_conversation.id);
    _bindRealtime();
    unawaited(_bootstrap());
  }

  void _bindRealtime() {
    final ws = widget.auth.ws;
    _subs.add(ws.onMessage.listen((m) => unawaited(_onIncomingMessage(m))));
    _subs.add(ws.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(() {});
      if (connected && !_conversation.isArchived) {
        ws.joinConversation(_conversation.id);
      }
    }));
    if (!_conversation.isArchived) {
      ws.joinConversation(_conversation.id);
    }
    _subs.add(ws.onGroupDissolved.listen(_onGroupDissolved));
    _subs.add(ws.onEpochUpdated.listen(_onEpochUpdated));
    _subs.add(ws.onConversationRemoved.listen(_onConversationRemoved));
    _subs.add(ws.onConversationUpdated.listen(_onConversationUpdated));
    _subs.add(ws.onConversationAdded.listen(_onConversationAdded));
    _subs.add(
      widget.auth.onConversationPatched.listen((conv) {
        if (!mounted || conv.id != _conversation.id) return;
        setState(() {
          _conversation = widget.auth.mergeConversationUpdate(_conversation, conv);
        });
      }),
    );
    if (_isGroup) {
      _subs.add(widget.auth.onGroupKeyReady.listen((convId) {
        if (convId == _conversation.id) unawaited(_refreshDecryption());
      }));
    }
  }

  @override
  void dispose() {
    VoiceHintToast.hide();
    if (_messages.isNotEmpty) {
      unawaited(
        widget.auth.markConversationRead(
          _conversation.id,
          upTo: _messages.last.createdAt,
        ),
      );
    }
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _scrollCoord.dispose();
    unawaited(_outgoing.dispose());
    widget.auth.setOpenConversation(null);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    if (VoiceHintToast.show(context, message)) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlySendError(String raw) {
    if (raw.contains('SocketException') || raw.contains('网络')) {
      return '发送失败，请检查网络后重试';
    }
    if (raw.contains('已退出群聊')) return '已退出群聊，无法发送';
    if (raw.contains('加密')) return raw;
    return '发送失败，点击红色感叹号重试';
  }

  bool _isStale(int epoch) => !mounted || epoch != _historyEpoch;

  Future<void> _markReadToLast() async {
    if (_messages.isEmpty) return;
    if (_scrollCoord.enterUnreadCount > 0 && _scrollCoord.showJumpToUnread) return;
    final last = _messages.last;
    await widget.auth.markConversationRead(_conversation.id, upTo: last.createdAt);
    if (!mounted) return;
    _scrollCoord.maybeMarkReadWithLast(last);
  }

  Future<void> _presentMessages(List<ChatMessage> list, {DateTime? readAt}) async {
    final at = readAt ?? await widget.auth.readAtFor(_conversation.id);
    final annReadIds = await widget.auth.announcementReadIdsFor(_conversation.id);
    final me = widget.auth.currentUser;
    final unread = math.max(
      widget.auth.countUnreadInThread(list, readAt: at),
      widget.initialUnreadCount,
    );
    setState(() {
      _messages = ChatThreadLoader.preserveLocalOutgoing(list, _messages);
      _error = null;
      _loading = false;
      _announcementReadIds = annReadIds;
      _scrollCoord.beginUnreadSession(readAt: at, unread: unread);
    });
    if (me != null) {
      _scrollCoord.bindThread(_messages, me.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollCoord.syncEnterUnreadBubbleAfterLayout();
        final focusId = _pendingFocusMessageId;
        if (focusId != null) {
          _pendingFocusMessageId = null;
          unawaited(_focusHistoryMessage(focusId));
        }
      });
    }
    unawaited(_thread.cacheIfReady(list));
    if (unread == 0) unawaited(_markReadToLast());
    unawaited(_prefetchChatImages(_messages));
  }

  Future<void> _prefetchChatImages(List<ChatMessage> messages) async {
    if (_conversation.isArchived) return;
    final pending = <ChatMessage>[];
    for (final m in messages) {
      if (m.type != 'image' || m.fileId == null || m.fileId!.isEmpty) continue;
      if (_prefetchingImages.contains(m.id)) continue;
      final needs = await MediaLocalCache.needsFullImageDownload(
        messageId: m.id,
        plaintext: m.plaintext,
        fileId: m.fileId,
      );
      if (!needs) continue;
      _prefetchingImages.add(m.id);
      pending.add(m);
    }
    if (pending.isEmpty) return;

    final repairs = <ChatMessage>[];
    for (final m in pending) {
      try {
        final repaired = await _repairMessageMediaQuiet(m.id);
        if (repaired != null) repairs.add(repaired);
      } finally {
        _prefetchingImages.remove(m.id);
      }
    }
    if (repairs.isEmpty || !mounted) return;
    setState(() {
      for (final repaired in repairs) {
        _messages = ChatThreadLoader.upsert(_messages, repaired);
        _thread.cacheMessageIfReady(_messages, repaired);
      }
    });
  }

  Future<ChatMessage?> _repairMessageMediaQuiet(String messageId) async {
    final i = _messages.indexWhere((m) => m.id == messageId);
    if (i < 0) return null;
    final prev = _messages[i];
    final repaired = await widget.auth.repairMessageMedia(_conversation, prev);
    if (repaired == null) return null;
    if (repaired.plaintext == prev.plaintext &&
        repaired.fileId == prev.fileId &&
        repaired.sendStatus == prev.sendStatus) {
      return null;
    }
    return repaired;
  }

  Future<void> _bootstrap() async {
    final reactivated = await widget.auth.tryReactivateConversation(_conversation);
    if (reactivated != null && mounted) {
      setState(() => _conversation = reactivated);
    }
    if (_isGroup && !_conversation.isArchived) {
      widget.auth.prepareGroupConversation(_conversation);
      unawaited(widget.auth.ensureGroupMemberDirectory(_conversation));
    }
    unawaited(_refreshConversationMetadata());
    await _loadHistory();
  }

  Future<void> _syncRemoteInBackground(int epoch) async {
    if (_conversation.isArchived || !mounted) return;
    try {
      final cached = await widget.auth.loadCachedMessages(_conversation.id);
      if (_isStale(epoch)) return;
      final list = await _thread.resolve(cached: cached, fetchRemote: true);
      if (_isStale(epoch) || !mounted) return;
      if (!_scrollCoord.tailPinned) {
        _scrollCoord.beginScrollLockForTailInsert();
      }
      setState(
        () => _messages = ChatThreadLoader.preserveLocalOutgoing(list, _messages),
      );
      final me = widget.auth.currentUser;
      if (me != null) _scrollCoord.bindThread(_messages, me.id);
      if (!_scrollCoord.tailPinned) {
        _scrollCoord.endScrollLockAfterTailInsert();
      }
      unawaited(_thread.cacheIfReady(_messages));
    } catch (_) {}
  }

  Future<void> _refreshConversationMetadata() async {
    if (_conversation.isArchived) return;
    try {
      final fresh = await widget.auth.refreshConversation(_conversation);
      if (mounted && !_conversation.isArchived) {
        setState(() => _conversation = fresh);
      }
    } catch (_) {}
  }

  Future<void> _presentQuickFromCache(
    List<ChatMessage> cached, {
    DateTime? readAt,
  }) async {
    if (cached.isEmpty || _messages.isNotEmpty) return;
    final quick = widget.auth.messagesForQuickDisplay(_conversation, cached);
    if (quick.isNotEmpty) await _presentMessages(quick, readAt: readAt);
  }

  Future<void> _loadHistory() async {
    final epoch = _historyEpoch;
    if (_messages.isEmpty) {
      setState(() => _error = null);
    }

    try {
      final readAt = await widget.auth.readAtFor(_conversation.id);
      if (_isStale(epoch)) return;

      final cached = await widget.auth.loadCachedMessages(_conversation.id);
      if (_isStale(epoch)) return;

      await _presentQuickFromCache(cached, readAt: readAt);

      final fullyLocal = cached.isNotEmpty &&
          await widget.auth.cachedMessagesFullyAvailable(cached);

      if (fullyLocal) {
        if (!_conversation.isArchived) {
          unawaited(_syncRemoteInBackground(epoch));
        }
        return;
      }

      final list = await _thread.resolve(
        cached: cached,
        fetchRemote: !_conversation.isArchived,
      );
      if (_isStale(epoch)) return;
      await _presentMessages(list, readAt: readAt);
    } catch (e) {
      if (_isStale(epoch)) return;
      if (_messages.isEmpty) {
        final cached = await widget.auth.loadCachedMessages(_conversation.id);
        if (cached.isNotEmpty) {
          final list = await _thread.resolve(cached: cached, fetchRemote: false);
          if (!mounted) return;
          await _presentMessages(list);
        } else {
          setState(() {
            _error = e.toString();
            _loading = false;
          });
        }
      } else {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _onPullRefresh() async {
    if (_conversation.isArchived) return;
    final epoch = _historyEpoch;
    try {
      await _refreshConversationMetadata();
      final cached = await widget.auth.loadCachedMessages(_conversation.id);
      final list = await _thread.resolve(cached: cached, fetchRemote: true);
      if (_isStale(epoch) || !mounted) return;
      if (!_scrollCoord.tailPinned) {
        _scrollCoord.beginScrollLockForTailInsert();
      }
      setState(
        () => _messages = ChatThreadLoader.preserveLocalOutgoing(list, _messages),
      );
      await _thread.cacheIfReady(_messages);
      if (!_scrollCoord.tailPinned) {
        _scrollCoord.endScrollLockAfterTailInsert();
      } else if (!_scrollCoord.isUserScrolling) {
        _scrollCoord.stickToTailIfPinned();
      }
    } catch (e) {
      if (mounted && _messages.isEmpty) setState(() => _error = e.toString());
    }
  }

  Future<void> _refreshDecryption() async {
    if (_messages.isEmpty || !mounted) return;
    final local = await widget.auth.decryptMessagesLocal(_conversation, _messages);
    if (!mounted) return;
    if (!_scrollCoord.tailPinned) {
      _scrollCoord.beginScrollLockForTailInsert();
    }
    setState(() {
      _messages = ChatThreadLoader.preserveLocalOutgoing(local, _messages);
    });
    unawaited(_thread.cacheIfReady(_messages));
    if (!_scrollCoord.tailPinned) {
      _scrollCoord.endScrollLockAfterTailInsert();
    } else if (!_loading) {
      _scrollCoord.stickToTailIfPinned();
    }
  }

  void _onMessagePending(ChatMessage msg) {
    setState(() {
      _messages = ChatThreadLoader.upsert(_messages, msg);
    });
    _scrollCoord.tailPinned = true;
    _scrollCoord.scrollToBottom(animated: true);
  }

  void _onMessageSent(String localId, ChatMessage msg) {
    setState(() {
      final i = _messages.indexWhere((m) => m.id == localId);
      if (i >= 0) {
        _messages = [..._messages.sublist(0, i), msg, ..._messages.sublist(i + 1)];
      } else {
        _messages = ChatThreadLoader.upsert(_messages, msg);
      }
      _thread.cacheMessageIfReady(_messages, msg);
    });
    _scrollCoord.tailPinned = true;
    _scrollCoord.scrollToBottom(animated: true);
  }

  void _onMessageFailed(String localId, String error) {
    setState(() {
      final i = _messages.indexWhere((m) => m.id == localId);
      if (i >= 0) {
        final failed = _messages[i].copyWith(sendStatus: MessageSendStatus.failed);
        _messages = [
          ..._messages.sublist(0, i),
          failed,
          ..._messages.sublist(i + 1),
        ];
        _thread.cacheMessageIfReady(_messages, failed);
      }
    });
    _showSnack(_friendlySendError(error));
  }

  bool _isMatchableOutgoing(ChatMessage m) =>
      m.isLocalOutgoing &&
      (m.sendStatus == MessageSendStatus.sending ||
          m.sendStatus == MessageSendStatus.failed);

  int? _outgoingEchoIndex(List<ChatMessage> list, ChatMessage echo, String meId) {
    if (echo.senderId != meId) return null;
    if (echo.fileId != null && echo.fileId!.isNotEmpty) {
      final byFile = list.indexWhere(
        (m) => _isMatchableOutgoing(m) && m.fileId == echo.fileId,
      );
      if (byFile >= 0) return byFile;
    }
    if (echo.type == 'text' && echo.plaintext != null) {
      final byText = list.indexWhere(
        (m) =>
            _isMatchableOutgoing(m) &&
            m.type == 'text' &&
            m.plaintext == echo.plaintext,
      );
      if (byText >= 0) return byText;
    }
    final byType = list.indexWhere(
      (m) => _isMatchableOutgoing(m) && m.type == echo.type,
    );
    return byType >= 0 ? byType : null;
  }

  Future<void> _onSendRetry(ChatMessage msg) async {
    final fileId = msg.fileId;
    if (fileId != null && fileId.isNotEmpty) {
      for (final existing in _messages) {
        if (!existing.isLocalOutgoing && existing.fileId == fileId) {
          _onMessageSent(
            msg.id,
            existing.copyWith(plaintext: msg.plaintext ?? existing.plaintext),
          );
          return;
        }
      }
    }
    await _outgoing.resend(msg);
  }

  Future<void> _markAnnouncementRead(ChatMessage ann) async {
    await widget.auth.markAnnouncementRead(_conversation.id, ann.id);
    if (!mounted) return;
    _applyAnnouncementRead(ann.id);
  }

  void _applyAnnouncementRead(String messageId) {
    setState(() => _announcementReadIds = {..._announcementReadIds, messageId});
  }

  Future<void> _reloadAnnouncementReadIds() async {
    final ids = await widget.auth.announcementReadIdsFor(_conversation.id);
    if (!mounted) return;
    setState(() => _announcementReadIds = ids);
  }

  Future<void> _openAnnouncements() async {
    await Navigator.of(context).push<void>(
      appPageRoute(
        builder: (_) => GroupAnnouncementsScreen(
          auth: widget.auth,
          conversation: _conversation,
          initialAnnouncements: AnnouncementRead.allOf(_messages),
        ),
      ),
    );
    if (!mounted) return;
    await _reloadAnnouncementReadIds();
  }

  Future<void> _openAnnouncementDetail(ChatMessage ann) async {
    final me = widget.auth.currentUser;
    if (me == null) return;
    await AnnouncementDetailScreen.open(
      context,
      msg: ann,
      publisherName: _nameFor(ann.senderId, me),
      onMarkRead: () => unawaited(_markAnnouncementRead(ann)),
    );
  }

  Future<void> _onIncomingMessage(ChatMessage msg) async {
    if (_conversation.isArchived ||
        msg.conversationId != _conversation.id ||
        !mounted) {
      return;
    }
    final materialized = await _thread.materializeIncoming(msg, _messages);
    if (!mounted) return;

    final me = widget.auth.currentUser;
    final fromPeer = me == null || materialized.senderId != me.id;
    final atBottom = _scrollCoord.isAtBottom;
    if (!atBottom) {
      _scrollCoord.beginScrollLockForTailInsert();
    }

    setState(() {
      var list = _messages;
      if (me != null) {
        final sendingIdx = _outgoingEchoIndex(list, materialized, me.id);
        if (sendingIdx != null) {
          list = [...list.sublist(0, sendingIdx), ...list.sublist(sendingIdx + 1)];
        }
      }
      _messages = ChatThreadLoader.upsert(list, materialized);
      _thread.cacheMessageIfReady(_messages, materialized);
    });
    if (me != null) _scrollCoord.bindThread(_messages, me.id);
    _scrollCoord.handleTailAfterMessage(
      atBottom: atBottom,
      fromPeer: fromPeer,
      messageId: materialized.id,
      messages: _messages,
      markRead: _markReadToLast,
    );
    if (atBottom) {
      _scrollCoord.tailPinned = true;
      _scrollCoord.stickToTailIfPinned();
    } else {
      _scrollCoord.endScrollLockAfterTailInsert();
    }
    unawaited(_prefetchChatImages([materialized]));
  }

  Future<void> _repairMessageMedia(
    String messageId, {
    void Function(double progress)? onProgress,
  }) async {
    final i = _messages.indexWhere((m) => m.id == messageId);
    if (i < 0 || !mounted) return;
    final repaired = await widget.auth.repairMessageMedia(
      _conversation,
      _messages[i],
      onProgress: onProgress,
    );
    if (repaired == null || !mounted) return;
    if (repaired.plaintext == _messages[i].plaintext &&
        repaired.fileId == _messages[i].fileId &&
        repaired.sendStatus == _messages[i].sendStatus) {
      return;
    }
    setState(() {
      _messages = ChatThreadLoader.upsert(_messages, repaired);
      _thread.cacheMessageIfReady(_messages, repaired);
    });
  }

  Future<void> _archiveAndReload() async {
    _historyEpoch++;
    setState(() => _conversation = _conversation.copyWith(isArchived: true));
    await _loadHistory();
  }

  Future<void> _onConversationAdded(ConversationAddedFrame frame) async {
    final conv = ConversationItem.fromJson(frame.conversation);
    if (conv.id != _conversation.id || !mounted) return;
    final active = await widget.auth.reactivateConversation(conv);
    if (!mounted) return;
    setState(() => _conversation = active);
    widget.auth.ws.joinConversation(active.id);
    await _loadHistory();
  }

  void _onConversationUpdated(ConversationUpdatedFrame frame) {
    if (!mounted) return;
    try {
      final conv = ConversationItem.fromJson(frame.conversation);
      if (conv.id != _conversation.id) return;
      setState(() {
        _conversation = widget.auth.mergeConversationUpdate(_conversation, conv);
      });
    } catch (_) {}
  }

  Future<void> _onEpochUpdated(EpochUpdatedFrame frame) async {
    if (frame.conversationId != _conversation.id || !mounted) return;
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (!mounted) return;
    setState(() => _conversation = fresh.copyWith(epoch: frame.epoch));
  }

  Future<void> _onConversationRemoved(ConversationRemovedFrame frame) async {
    if (frame.conversationId != _conversation.id || !mounted) return;
    final showUi = widget.auth.claimRemovalUi(frame.conversationId);
    await widget.auth.handleConversationRemoved(
      frame.conversationId,
      snapshot: _conversation,
      messages: _messages,
    );
    if (!mounted) return;
    await _archiveAndReload();
    if (!mounted || !showUi) return;
    _showSnack('你已被移出该群聊，仍可查看历史消息');
  }

  Future<void> _onGroupDissolved(GroupDissolvedFrame frame) async {
    if (frame.conversationId != _conversation.id || !mounted) return;
    final me = widget.auth.currentUser;
    if (me == null) return;
    final isSelf = frame.dissolvedBy == me.id;
    await widget.auth.handleGroupDissolved(frame.conversationId);

    if (!isSelf) {
      final name = frame.groupName.isNotEmpty
          ? frame.groupName
          : _conversation.displayTitle(me.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('群聊已解散'),
          content: Text('群聊「$name」已被解散'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
          ],
        ),
      );
    }
    if (mounted) Navigator.of(context).pop('dissolved');
  }

  String? _avatarUrlFor(String userId, User me) {
    if (userId == me.id) return me.avatarUrl;
    return widget.auth.groupMemberAvatarUrl(_conversation, userId);
  }

  String _nameFor(String userId, User me) {
    if (userId == me.id) return me.username;
    return widget.auth.groupMemberUsername(_conversation, userId);
  }

  void _openUserDetail(String userId) {
    final me = widget.auth.currentUser;
    if (me == null || userId == me.id) return;
    final member = widget.auth.knownGroupMember(_conversation, userId);
    if (member == null) return;
    openUserDetailFromMember(
      context,
      auth: widget.auth,
      member: member,
      groupContext: _isGroup ? _conversation : null,
    );
  }

  Future<void> _focusHistoryMessage(String? messageId) async {
    if (messageId == null || messageId.isEmpty) return;
    if (_messages.isEmpty) {
      await _loadHistory();
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _scrollCoord.scrollToMessage(messageId);
      _scrollCoord.focusMessage(messageId);
    });
  }

  Future<void> _openConversationMenu() async {
    if (_isGroup) {
      await _openGroupManage();
      return;
    }
    final jump = await Navigator.of(context).push<ChatHistoryJump>(
      appPageRoute(
        builder: (_) => ChatSettingsScreen(
          auth: widget.auth,
          conversation: _conversation,
        ),
      ),
    );
    if (!mounted) return;
    if (jump != null) await _focusHistoryMessage(jump.messageId);
  }

  Future<void> _openGroupManage() async {
    final result = await Navigator.of(context).push<Object?>(
      appPageRoute(
        builder: (_) => GroupManageScreen(auth: widget.auth, conversation: _conversation),
      ),
    );
    if (!mounted) return;
    if (result is ChatHistoryJump) {
      await _focusHistoryMessage(result.messageId);
      return;
    }
    if (result == 'left') {
      await _archiveAndReload();
      return;
    }
    if (result == 'dissolved') {
      await _thread.cacheIfReady(_messages);
      if (!mounted) return;
      Navigator.of(context).pop(result);
      return;
    }
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (mounted) setState(() => _conversation = fresh);
    await _loadHistory();
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _outgoing.sendText(text);
  }

  Future<void> _openCloudDrive() async {
    try {
      await CloudDriveLauncher.open();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<LargeFileSendChoice> _promptLargeFile(int byteSize) async {
    final sizeLabel = formatFileSizeMb(byteSize);
    final limitLabel = formatFileSizeMb(AppConfig.maxFileBytes);
    final choice = await showDialog<LargeFileSendChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文件较大'),
        content: Text(
          '该文件约 $sizeLabel，超过 $limitLabel 建议使用 ${CloudDriveLauncher.label} 分享。\n'
          '您也可以仍通过 IM 直接发送（上限 $limitLabel）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, LargeFileSendChoice.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, LargeFileSendChoice.sendViaIm),
            child: const Text('仍发送文件'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, LargeFileSendChoice.cloudDrive),
            child: Text('打开${CloudDriveLauncher.label}'),
          ),
        ],
      ),
    );
    return choice ?? LargeFileSendChoice.cancel;
  }

  ConversationMember? _peerMember(User me) {
    if (_isGroup) return null;
    for (final m in _conversation.members) {
      if (m.userId != me.id) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _buildChat(me);
  }

  Widget _buildChat(User me) {
    final isArchived = _conversation.isArchived;
    final peer = _peerMember(me);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted || _popInProgress) return;
        _popInProgress = true;
        final navigator = Navigator.of(context);
        try {
          if (!isArchived && _messages.isNotEmpty) {
            await widget.auth.markConversationRead(
              _conversation.id,
              upTo: _messages.last.createdAt,
            );
          }
          if (!mounted) return;
          navigator.pop(isArchived ? 'left' : null);
        } finally {
          _popInProgress = false;
        }
      },
      child: Scaffold(
        appBar: ChatAppBar(
          conversation: _conversation,
          me: me,
          isGroup: _isGroup,
          isArchived: isArchived,
          onTitleTap: peer != null ? () => _openUserDetail(peer.userId) : null,
          onAnnouncements:
              _isGroup && !isArchived ? () => unawaited(_openAnnouncements()) : null,
          announcementUnread: _announcementUnread,
          onMenu: () => unawaited(_openConversationMenu()),
        ),
        body: Column(
          children: [
            if (!widget.auth.ws.isConnected)
              OfflineBanner(
                message: '网络已断开，消息可能无法收发',
                onRetry: () => unawaited(widget.auth.reconnectRealtime()),
              ),
            if (isArchived)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('你已退出此群聊，仅可查看历史消息')),
                  ],
                ),
              ),
            if (_isGroup && !isArchived)
              for (final ann in _visibleUnreadAnnouncementBanners)
                GroupAnnouncementBanner(
                  announcement: ann,
                  isUnread: true,
                  onTap: () => _openAnnouncementDetail(ann),
                  onDismiss: () => _dismissAnnouncementBanner(ann.id),
                ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ChatMessageListView(
                    error: _error,
                    messages: _messages,
                    conversation: _conversation,
                    isGroup: _isGroup,
                    isArchived: isArchived,
                    scrollController: _scroll,
                    scrollCoord: _scrollCoord,
                    me: me,
                    nameFor: (id) => _nameFor(id, me),
                    avatarUrlFor: (id) => _avatarUrlFor(id, me),
                    onPeerTap: _openUserDetail,
                    onMediaRetry: _repairMessageMedia,
                    onSendRetry: (msg) => unawaited(_onSendRetry(msg)),
                    announcementReadIds: _announcementReadIds,
                    onAnnouncementTap: (msg) => unawaited(_openAnnouncementDetail(msg)),
                    onRefresh: _onPullRefresh,
                  ),
                  ChatFloatingChips(
                    scrollCoord: _scrollCoord,
                    messages: _messages,
                  ),
                ],
              ),
            ),
            if (!isArchived)
              ChatInputBar(
                controller: _input,
                sending: _outgoing.isRecording,
                onSend: () => unawaited(_sendText()),
                onVoiceHoldStart: _outgoing.startVoiceRecord,
                onVoiceHoldEnd: _outgoing.finishVoiceRecord,
                onImage: () => unawaited(_outgoing.pickImage()),
                onCamera: () => unawaited(_outgoing.captureImage()),
                onFile: () => unawaited(_outgoing.pickFile()),
                onCloudDrive: () => unawaited(_openCloudDrive()),
              ),
          ],
        ),
      ),
    );
  }
}
