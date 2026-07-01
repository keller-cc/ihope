import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/offline_banner.dart';
import 'chat/chat_app_bar.dart';
import 'chat/chat_message_list_view.dart';
import 'chat/chat_message_tile.dart';
import 'chat/chat_outgoing_controller.dart';
import 'chat/chat_scroll_coordinator.dart';
import 'chat/chat_thread_loader.dart';
import 'chat_settings_screen.dart';
import 'group_manage_screen.dart';
import 'user_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.auth,
    required this.conversation,
    this.initialUnreadCount = 0,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final int initialUnreadCount;

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
  bool _loading = true;
  String? _error;
  int _historyEpoch = 0;

  bool get _isGroup => _conversation.type == 'group';

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _thread = ChatThreadLoader(auth: widget.auth, conversation: _conversation);

    _scrollCoord = ChatScrollCoordinator(
      scrollController: _scroll,
      onChanged: () {
        if (mounted) setState(() {});
      },
      isMounted: () => mounted,
      onReachedBottom: () => unawaited(_markReadToLast()),
      firstUnreadIndexIn: (msgs, readAt) =>
          widget.auth.firstUnreadIndexInThread(msgs, readAt: readAt),
    );
    _scrollCoord.attach();

    _outgoing = ChatOutgoingController(
      auth: widget.auth,
      conversation: () => _conversation,
      onPending: _onMessagePending,
      onSent: _onMessageSent,
      onFailed: _onMessageFailed,
      onError: _showSnack,
    );

    widget.auth.setOpenConversation(_conversation.id);
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
    if (_isGroup) {
      _subs.add(widget.auth.onGroupKeyReady.listen((convId) {
        if (convId == _conversation.id) unawaited(_refreshDecryption());
      }));
    }
  }

  @override
  void dispose() {
    if (_scrollCoord.tailPinned &&
        _messages.isNotEmpty &&
        !_scrollCoord.showJumpToUnread &&
        _scrollCoord.enterUnreadCount == 0) {
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
    _scrollCoord.detach();
    unawaited(_outgoing.dispose());
    widget.auth.setOpenConversation(null);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
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
    final unread = math.max(
      widget.auth.countUnreadInThread(list, readAt: at),
      widget.initialUnreadCount,
    );
    setState(() {
      _messages = ChatThreadLoader.preserveLocalOutgoing(list, _messages);
      _error = null;
      _loading = false;
      _scrollCoord.applyReadSnapshot(readAt: at, unread: unread);
    });
    unawaited(_thread.cacheIfReady(list));
    if (unread == 0) unawaited(_markReadToLast());
  }

  Future<void> _bootstrap() async {
    final reactivated = await widget.auth.tryReactivateConversation(_conversation);
    if (reactivated != null && mounted) {
      setState(() => _conversation = reactivated);
    }
    if (_isGroup && !_conversation.isArchived) {
      widget.auth.prepareGroupConversation(_conversation);
      await widget.auth.ensureGroupMemberDirectory(_conversation);
    }
    unawaited(_refreshConversationMetadata());
    await _loadHistory();
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

  Future<void> _loadHistory() async {
    final epoch = _historyEpoch;
    if (_messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final readAt = await widget.auth.readAtFor(_conversation.id);
      if (_isStale(epoch)) return;

      final cached = await widget.auth.loadCachedMessages(_conversation.id);
      if (_isStale(epoch)) return;

      final fullyLocal = cached.isNotEmpty &&
          await widget.auth.cachedMessagesFullyAvailable(cached);

      final list = await _thread.resolve(
        cached: cached,
        fetchRemote: !fullyLocal || _conversation.isArchived,
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
      setState(
        () => _messages = ChatThreadLoader.preserveLocalOutgoing(list, _messages),
      );
      await _thread.cacheIfReady(_messages);
      if (_scrollCoord.tailPinned) _scrollCoord.stickToTailIfPinned();
    } catch (e) {
      if (mounted && _messages.isEmpty) setState(() => _error = e.toString());
    }
  }

  Future<void> _refreshDecryption() async {
    if (_messages.isEmpty || !mounted) return;
    final local = await widget.auth.decryptMessagesLocal(_conversation, _messages);
    if (!mounted) return;
    setState(() => _messages = local);
    unawaited(_thread.cacheIfReady(local));
    if (_scrollCoord.tailPinned && !_loading) {
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
        _messages = [
          ..._messages.sublist(0, i),
          _messages[i].copyWith(sendStatus: MessageSendStatus.failed),
          ..._messages.sublist(i + 1),
        ];
      }
    });
    _showSnack(_friendlySendError(error));
  }

  Future<void> _onSendRetry(ChatMessage msg) async {
    await _outgoing.resend(msg);
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

    setState(() {
      var list = _messages;
      if (me != null && materialized.senderId == me.id) {
        final sendingIdx = list.indexWhere(
          (m) =>
              m.isLocalOutgoing &&
              m.sendStatus == MessageSendStatus.sending &&
              m.type == materialized.type,
        );
        if (sendingIdx >= 0) {
          list = [...list.sublist(0, sendingIdx), ...list.sublist(sendingIdx + 1)];
        }
      }
      _messages = ChatThreadLoader.upsert(list, materialized);
      _thread.cacheMessageIfReady(_messages, materialized);
    });
    _scrollCoord.handleTailAfterMessage(
      atBottom: atBottom,
      fromPeer: fromPeer,
      messages: _messages,
      markRead: _markReadToLast,
    );
  }

  Future<void> _repairMessageMedia(String messageId) async {
    final i = _messages.indexWhere((m) => m.id == messageId);
    if (i < 0) return;
    final repaired = await widget.auth.repairMessageMedia(_conversation, _messages[i]);
    if (repaired == null || !mounted) return;
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

  Future<void> _openConversationMenu() async {
    if (_isGroup) {
      await _openGroupManage();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatSettingsScreen(auth: widget.auth, conversation: _conversation),
      ),
    );
  }

  Future<void> _openGroupManage() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => GroupManageScreen(auth: widget.auth, conversation: _conversation),
      ),
    );
    if (!mounted) return;
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
      return const Scaffold(body: Center(child: Text('未登录')));
    }

    final isArchived = _conversation.isArchived;
    final peer = _peerMember(me);

    return PopScope(
      canPop: !isArchived,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isArchived || !mounted) return;
        Navigator.of(context).pop('left');
      },
      child: Scaffold(
        appBar: ChatAppBar(
          conversation: _conversation,
          me: me,
          isGroup: _isGroup,
          isArchived: isArchived,
          onTitleTap: peer != null ? () => _openUserDetail(peer.userId) : null,
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
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ChatMessageListView(
                    loading: _loading,
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
                    onRefresh: _onPullRefresh,
                  ),
                  ChatFloatingChips(
                    showJumpToUnread: _scrollCoord.showJumpToUnread,
                    showJumpToBottom: _scrollCoord.showJumpToBottom,
                    enterUnreadCount: _scrollCoord.enterUnreadCount,
                    belowUnreadCount: _scrollCoord.belowUnreadCount,
                    onJumpToUnread: () => _scrollCoord.onJumpToUnread(_messages),
                    onJumpToBottom: () =>
                        _scrollCoord.onJumpToBottom(_messages, _markReadToLast),
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
                onFile: () => unawaited(_outgoing.pickFile()),
                onEmoji: () => _showSnack('表情功能即将上线'),
              ),
          ],
        ),
      ),
    );
  }
}
