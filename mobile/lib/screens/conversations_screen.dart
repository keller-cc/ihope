import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

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
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.auth.conversations.listConversations();
      if (!mounted) return;
      setState(() => _items = items);
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
    await _load();
  }

  Future<void> _openNewChat() async {
    final conv = await Navigator.of(context).push<ConversationItem>(
      MaterialPageRoute(
        builder: (_) => NewChatScreen(auth: widget.auth),
      ),
    );
    if (conv != null && mounted) {
      await _load();
      if (!mounted) return;
      await _openChat(conv);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: Text('你好，${me.username}'),
        actions: [
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
                          final preview =
                              item.lastMessage?.ciphertext ?? '暂无消息';
                          return ListTile(
                            title: Text(item.displayTitle(me.id)),
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
