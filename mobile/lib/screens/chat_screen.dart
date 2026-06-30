import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../utils/message_time.dart';
import '../widgets/realtime_indicator.dart';
import '../widgets/user_avatar.dart';

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

  List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    _msgSub = widget.auth.ws.onMessage.listen(_onIncomingMessage);
    _connSub = widget.auth.ws.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(() {});
      if (connected) {
        widget.auth.ws.joinConversation(widget.conversation.id);
      }
    });
    widget.auth.ws.joinConversation(widget.conversation.id);
    _bootstrap();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onIncomingMessage(ChatMessage msg) {
    if (msg.conversationId != widget.conversation.id) return;
    if (!mounted) return;
    setState(() => _addMessage(msg));
    _scrollToBottom();
  }

  Future<void> _bootstrap() async {
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msgs = await widget.auth.conversations.listMessages(
        widget.conversation.id,
        limit: 100,
      );
      if (!mounted) return;
      setState(() => _messages = msgs);
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addMessage(ChatMessage msg) {
    if (_messages.any((m) => m.id == msg.id)) return;
    _messages = [..._messages, msg];
  }

  String? _avatarUrlFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.avatarUrl;
    for (final m in widget.conversation.members) {
      if (m.userId == userId) return m.avatarUrl;
    }
    return null;
  }

  String _nameFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.username;
    for (final m in widget.conversation.members) {
      if (m.userId == userId) return m.username;
    }
    return '?';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      final msg = await widget.auth.conversations.sendMessage(
        widget.conversation.id,
        text,
      );
      if (!mounted) return;
      setState(() => _addMessage(msg));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    final title = widget.conversation.displayTitle(me.id);
    final peerAvatar = widget.conversation.peerAvatarUrl(me.id);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: title,
              imageUrl: peerAvatar,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
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
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '输入下方内容，发送第一条消息',
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
                            controller: _scroll,
                            padding: const EdgeInsets.all(12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final prev =
                                  index > 0 ? _messages[index - 1] : null;
                              final showTime =
                                  MessageTimeFormat.shouldShowDivider(
                                prev?.createdAt,
                                msg.createdAt,
                              );
                              final mine = msg.senderId == me.id;
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  if (showTime)
                                    _TimeDivider(
                                      label: MessageTimeFormat.formatDivider(
                                        msg.createdAt,
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      mainAxisAlignment: mine
                                          ? MainAxisAlignment.end
                                          : MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (!mine) ...[
                                          UserAvatar(
                                            name: _nameFor(msg.senderId),
                                            imageUrl:
                                                _avatarUrlFor(msg.senderId),
                                            radius: 16,
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Flexible(
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.sizeOf(
                                                      context)
                                                  .width *
                                                  0.65,
                                            ),
                                            child: Column(
                                              crossAxisAlignment: mine
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: mine
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerHighest,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(msg.ciphertext),
                                                ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    top: 2,
                                                    left: 4,
                                                    right: 4,
                                                  ),
                                                  child: Text(
                                                    MessageTimeFormat
                                                        .formatBubble(
                                                      msg.createdAt,
                                                    ),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                          fontSize: 11,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
          ),
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
    );
  }
}

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.label});

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
