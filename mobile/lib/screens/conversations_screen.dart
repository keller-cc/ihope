import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../widgets/realtime_indicator.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'profile_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    super.key,
    required this.auth,
    required this.onLogout,
  });

  final AuthService auth;
  final Future<void> Function() onLogout;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<ConversationItem> _items = [];
  final Map<String, String> _previews = {};
  bool _loading = true;
  String? _error;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    _load();
    _msgSub = widget.auth.ws.onMessage.listen(_onIncomingMessage);
    _connSub = widget.auth.ws.onConnectionChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  void _onIncomingMessage(ChatMessage msg) {
    if (!mounted) return;

    final index = _items.indexWhere((c) => c.id == msg.conversationId);
    if (index < 0) {
      _load();
      return;
    }

    final conv = _items[index];
    unawaited(_applyIncomingPreview(conv, msg));
  }

  Future<void> _applyIncomingPreview(
    ConversationItem conv,
    ChatMessage msg,
  ) async {
    final preview = await widget.auth.decryptPreview(conv, msg);
    if (!mounted) return;
    final updated = conv.copyWith(lastMessage: msg);
    setState(() {
      _previews[conv.id] = preview;
      _items = [
        updated,
        ..._items.where((c) => c.id != conv.id),
      ];
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.reconnectRealtime();
      final items = await widget.auth.conversations.listConversations();
      final previews = <String, String>{};
      for (final item in items) {
        final last = item.lastMessage;
        if (last != null) {
          previews[item.id] =
              await widget.auth.decryptPreview(item, last);
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _previews
          ..clear()
        ..addAll(previews);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat(ConversationItem conv) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(auth: widget.auth, conversation: conv),
      ),
    );
  }

  Future<void> _openProfile() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          auth: widget.auth,
          onProfileUpdated: () => setState(() {}),
        ),
      ),
    );
    if (result == 'logout' && mounted) {
      await widget.onLogout();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openNewChat() async {
    final conv = await Navigator.of(context).push<ConversationItem>(
      MaterialPageRoute(
        builder: (_) => NewChatScreen(auth: widget.auth),
      ),
    );
    if (conv != null && mounted) {
      setState(() {
        if (!_items.any((c) => c.id == conv.id)) {
          _items = [conv, ..._items];
        }
      });
      if (!mounted) return;
      await _openChat(conv);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: me.username,
              imageUrl: me.avatarUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '你好，${me.username}',
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
          IconButton(
            tooltip: '个人资料',
            onPressed: _openProfile,
            icon: const Icon(Icons.person),
          ),
          IconButton(
            tooltip: '退出',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewChat,
        child: const Icon(Icons.chat),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('暂无会话，点右下角发起单聊')),
                        ],
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final preview = item.lastMessage == null
                              ? '暂无消息'
                              : (_previews[item.id] ??
                                  item.lastMessage!.displayText);
                          final peerName = item.peerDisplayName(me.id);
                          return ListTile(
                            leading: UserAvatar(
                              name: peerName,
                              imageUrl: item.peerAvatarUrl(me.id),
                            ),
                            title: Text(peerName),
                            subtitle: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _openChat(item),
                          );
                        },
                      ),
      ),
    );
  }
}
