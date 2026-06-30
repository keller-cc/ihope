import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../utils/message_time.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/realtime_indicator.dart';
import '../widgets/user_avatar.dart';
import 'group_manage_screen.dart';
import 'user_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  late ConversationItem _conversation;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _pinned = false;
  String? _error;
  int _historyEpoch = 0;
  bool _tailPinned = true;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<GroupDissolvedFrame>? _dissolvedSub;
  StreamSubscription<EpochUpdatedFrame>? _epochSub;
  StreamSubscription<ConversationRemovedFrame>? _removedSub;
  StreamSubscription<ConversationUpdatedFrame>? _updatedSub;
  StreamSubscription<ConversationAddedFrame>? _addedSub;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _msgSub = widget.auth.ws.onMessage.listen((msg) {
      unawaited(_onIncomingMessage(msg));
    });
    _connSub = widget.auth.ws.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(() {});
      if (connected && !_conversation.isArchived) {
        widget.auth.ws.joinConversation(_conversation.id);
      }
    });
    if (!_conversation.isArchived) {
      widget.auth.ws.joinConversation(_conversation.id);
    }
    _scroll.addListener(() => _tailPinned = _isNearBottom());
    _loadPinState();
    _bootstrap();
    _dissolvedSub = widget.auth.ws.onGroupDissolved.listen(_onGroupDissolved);
    _epochSub = widget.auth.ws.onEpochUpdated.listen(_onEpochUpdated);
    _removedSub =
        widget.auth.ws.onConversationRemoved.listen(_onConversationRemoved);
    _updatedSub =
        widget.auth.ws.onConversationUpdated.listen(_onConversationUpdated);
    _addedSub =
        widget.auth.ws.onConversationAdded.listen(_onConversationAdded);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _dissolvedSub?.cancel();
    _epochSub?.cancel();
    _removedSub?.cancel();
    _updatedSub?.cancel();
    _addedSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _isStale(int epoch) => !mounted || epoch != _historyEpoch;

  void _bumpHistoryEpoch() => _historyEpoch++;

  bool _isNearBottom([double threshold = 80]) {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels <= threshold;
  }

  bool _tailChanged(List<ChatMessage> before, List<ChatMessage> after) {
    if (after.isEmpty) return false;
    if (before.isEmpty) return true;
    if (after.length != before.length) return true;
    return after.last.id != before.last.id;
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> primary,
    List<ChatMessage> secondary,
  ) {
    final byId = {for (final m in primary) m.id: m};
    for (final m in secondary) {
      byId.putIfAbsent(m.id, () => m);
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<ChatMessage> _displayableMessages(List<ChatMessage> msgs) {
    return msgs
        .map(
          (m) => m.type == 'system'
              ? m.copyWith(plaintext: m.plaintext ?? m.ciphertext)
              : m,
        )
        .toList();
  }

  Future<List<ChatMessage>> _fetchMergedMessages(
    List<ChatMessage> cached,
  ) async {
    try {
      final remote = await widget.auth.conversations.listMessages(
        _conversation.id,
        limit: 100,
      );
      return cached.isEmpty ? remote : _mergeMessages(remote, cached);
    } catch (_) {
      return cached;
    }
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (animated) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(0);
      }
    });
  }

  Future<void> _bootstrap() async {
    final reactivated =
        await widget.auth.tryReactivateConversation(_conversation);
    if (reactivated != null && mounted) {
      setState(() => _conversation = reactivated);
    }
    unawaited(_refreshConversationMetadata());
    await _loadHistory();
  }

  Future<void> _refreshConversationMetadata() async {
    if (_conversation.isArchived) return;
    try {
      final fresh = await widget.auth.refreshConversation(_conversation);
      if (!mounted || _conversation.isArchived) return;
      setState(() => _conversation = fresh);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    final epoch = _historyEpoch;
    final archived = _conversation.isArchived;

    if (_messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      var msgs = await widget.auth.loadCachedMessages(_conversation.id);
      if (_isStale(epoch)) return;

      if (_messages.isEmpty && msgs.isNotEmpty) {
        setState(() {
          _messages = _displayableMessages(msgs);
          _loading = false;
          _tailPinned = true;
        });
      }

      msgs = await _fetchMergedMessages(msgs);
      if (_isStale(epoch) || _conversation.isArchived != archived) return;

      if (archived) {
        setState(() {
          _messages = _displayableMessages(msgs);
          _error = null;
        });
        if (_messages.isNotEmpty) {
          await widget.auth.cacheMessages(_conversation.id, _messages);
        }
        return;
      }

      if (_conversation.type == 'group') {
        await widget.auth.ensureGroupKeysForMessages(_conversation, msgs);
      }
      if (_isStale(epoch) || _conversation.isArchived) return;

      final before = _messages;
      final decrypted = await widget.auth.decryptMessages(_conversation, msgs);
      if (_isStale(epoch)) return;

      final tailChanged = _tailChanged(before, decrypted);
      setState(() => _messages = decrypted);
      await widget.auth.cacheMessages(_conversation.id, decrypted);
      if ((_tailPinned || before.isEmpty) && tailChanged) {
        _scrollToBottom(animated: _tailPinned && before.isNotEmpty);
      }
    } catch (e) {
      if (_isStale(epoch)) return;
      if (_messages.isEmpty) {
        final cached = await widget.auth.loadCachedMessages(_conversation.id);
        if (cached.isNotEmpty) {
          setState(() {
            _messages = _displayableMessages(cached);
            _error = null;
            _tailPinned = true;
          });
        } else {
          setState(() => _error = e.toString());
        }
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (!_isStale(epoch)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _archiveAndReload() async {
    _bumpHistoryEpoch();
    setState(() => _conversation = _conversation.copyWith(isArchived: true));
    await _loadHistory();
  }

  void _addMessage(ChatMessage msg) {
    if (_messages.any((m) => m.id == msg.id)) return;
    _messages = [..._messages, msg];
    unawaited(widget.auth.cacheMessages(_conversation.id, _messages));
  }

  Future<void> _onConversationAdded(ConversationAddedFrame frame) async {
    final conv = ConversationItem.fromJson(frame.conversation);
    if (conv.id != _conversation.id) return;
    if (!mounted) return;
    final active = await widget.auth.reactivateConversation(conv);
    if (!mounted) return;
    setState(() => _conversation = active);
    widget.auth.ws.joinConversation(active.id);
    await _loadHistory();
  }

  void _onConversationUpdated(ConversationUpdatedFrame frame) {
    final conv = ConversationItem.fromJson(frame.conversation);
    if (conv.id != _conversation.id) return;
    if (!mounted) return;
    setState(() {
      _conversation = widget.auth.mergeConversationUpdate(_conversation, conv);
    });
  }

  Future<void> _onEpochUpdated(EpochUpdatedFrame frame) async {
    if (frame.conversationId != _conversation.id) return;
    if (!mounted) return;
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (!mounted) return;
    setState(() => _conversation = fresh.copyWith(epoch: frame.epoch));
  }

  Future<void> _onConversationRemoved(ConversationRemovedFrame frame) async {
    if (frame.conversationId != _conversation.id) return;
    if (!mounted) return;
    final showUi = widget.auth.claimRemovalUi(frame.conversationId);
    await widget.auth.handleConversationRemoved(
      frame.conversationId,
      snapshot: _conversation,
      messages: _messages,
    );
    if (!mounted) return;
    await _archiveAndReload();
    if (!mounted || !showUi) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('你已被移出该群聊，仍可查看历史消息')),
    );
  }

  Future<void> _onGroupDissolved(GroupDissolvedFrame frame) async {
    if (frame.conversationId != _conversation.id) return;
    if (!mounted) return;

    final me = widget.auth.currentUser!;
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop('dissolved');
    }
  }

  Future<void> _loadPinState() async {
    final pinned =
        await widget.auth.isConversationPinned(_conversation.id);
    if (mounted) setState(() => _pinned = pinned);
  }

  Future<void> _onIncomingMessage(ChatMessage msg) async {
    if (_conversation.isArchived) return;
    if (msg.conversationId != _conversation.id) return;
    if (!mounted) return;
    if (msg.type == 'system') {
      setState(
        () => _addMessage(msg.copyWith(plaintext: msg.ciphertext)),
      );
    } else {
      final decrypted =
          await widget.auth.decryptMessage(_conversation, msg);
      if (!mounted) return;
      setState(() => _addMessage(decrypted));
    }
    if (_tailPinned) _scrollToBottom(animated: true);
  }

  String? _avatarUrlFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.avatarUrl;
    for (final m in _conversation.members) {
      if (m.userId == userId) return m.avatarUrl;
    }
    return null;
  }

  String _nameFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.username;
    for (final m in _conversation.members) {
      if (m.userId == userId) return m.username;
    }
    return '?';
  }

  ConversationMember? _memberFor(String userId) {
    for (final m in _conversation.members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  void _openUserDetail(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return;

    final member = _memberFor(userId);
    if (member != null) {
      openUserDetailFromMember(
        context,
        auth: widget.auth,
        member: member,
        groupContext: _conversation.type == 'group' ? _conversation : null,
      );
    }
  }

  Future<void> _togglePin() async {
    await widget.auth.setConversationPinned(
      _conversation.id,
      pinned: !_pinned,
    );
    if (!mounted) return;
    setState(() => _pinned = !_pinned);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_pinned ? '已置顶' : '已取消置顶')),
    );
  }

  Future<void> _openGroupManage() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => GroupManageScreen(
          auth: widget.auth,
          conversation: _conversation,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'left') {
      await _archiveAndReload();
      return;
    }
    if (result == 'dissolved') {
      await widget.auth.cacheMessages(_conversation.id, _messages);
      if (!mounted) return;
      Navigator.of(context).pop(result);
      return;
    }
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (mounted) setState(() => _conversation = fresh);
    await _loadHistory();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      final msg = await widget.auth.sendChatMessage(
        _conversation,
        text,
      );
      if (!mounted) return;
      setState(() => _addMessage(msg));
      _tailPinned = true;
      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      _input.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _buildMessageItem({
    required BuildContext context,
    required User me,
    required ChatMessage msg,
    required ChatMessage? prev,
    required bool isGroup,
  }) {
    final showTime = MessageTimeFormat.shouldShowDivider(
      prev?.createdAt,
      msg.createdAt,
    );
    final timeDivider = showTime
        ? MessageTimeDivider(
            label: MessageTimeFormat.formatDivider(msg.createdAt),
          )
        : null;

    if (msg.type == 'system') {
      return Column(
        key: ValueKey(msg.id),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (timeDivider != null) timeDivider,
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                msg.displayText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      key: ValueKey(msg.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timeDivider != null) timeDivider,
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ChatBubble(
            msg: msg,
            mine: msg.senderId == me.id,
            isGroup: isGroup,
            me: me,
            senderTitle: _conversation.memberTitle(msg.senderId),
            nameFor: _nameFor,
            avatarUrlFor: _avatarUrlFor,
            onPeerTap: _openUserDetail,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('未登录')),
      );
    }
    final title = _conversation.displayTitle(me.id);
    final avatarUrl = _conversation.displayAvatarUrl(me.id);
    final isGroup = _conversation.type == 'group';
    ConversationMember? peerMember;
    if (!isGroup) {
      for (final m in _conversation.members) {
        if (m.userId != me.id) {
          peerMember = m;
          break;
        }
      }
    }
    final isArchived = _conversation.isArchived;
    return PopScope(
      canPop: !isArchived,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !isArchived || !mounted) return;
        Navigator.of(context).pop('left');
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: peerMember != null
                ? () => _openUserDetail(peerMember!.userId)
                : null,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                UserAvatar(
                  name: title,
                  imageUrl: avatarUrl,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isGroup && !isArchived)
                        Text(
                          '${_conversation.members.length} 人',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (isArchived)
                        Text(
                          '已退出 · 只读',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              tooltip: _pinned ? '取消置顶' : '置顶会话',
              icon: Icon(
                _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _pinned
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: _togglePin,
            ),
            if (isGroup && !isArchived)
              IconButton(
                tooltip: '群管理',
                icon: const Icon(Icons.settings),
                onPressed: _openGroupManage,
              ),
            RealtimeIndicator(
              connected: widget.auth.ws.isConnected,
              onReconnect: widget.auth.ws.isConnected
                  ? null
                  : () => widget.auth.reconnectRealtime(),
            ),
          ],
        ),
        body: Column(
          children: [
            if (isArchived)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('你已退出此群聊，仅可查看历史消息'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _messages.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline,
                                      size: 48,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '暂无消息',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isArchived
                                          ? '此会话暂无历史消息'
                                          : '下方输入内容，发送第一条消息',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              reverse: true,
                              controller: _scroll,
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msgIndex =
                                    _messages.length - 1 - index;
                                final msg = _messages[msgIndex];
                                final prev = msgIndex > 0
                                    ? _messages[msgIndex - 1]
                                    : null;
                                return _buildMessageItem(
                                  context: context,
                                  me: me,
                                  msg: msg,
                                  prev: prev,
                                  isGroup: isGroup,
                                );
                              },
                            ),
            ),
            if (!isArchived)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          decoration: const InputDecoration(
                            hintText: '输入消息…',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
