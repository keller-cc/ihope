import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../utils/text_search.dart';
import 'chat_history_jump.dart';
import 'chat_history_loader.dart';
import 'widgets/chat_history_result_tile.dart';

/// 全文搜索：历史记录、关键字高亮、点击返回会话定位。
class ChatHistorySearchScreen extends StatefulWidget {
  const ChatHistorySearchScreen({
    super.key,
    required this.auth,
    required this.conversation,
    required this.loader,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final ChatHistoryLoader loader;

  @override
  State<ChatHistorySearchScreen> createState() =>
      _ChatHistorySearchScreenState();
}

class _ChatHistorySearchScreenState extends State<ChatHistorySearchScreen> {
  final _query = TextEditingController();
  List<ChatMessage> _all = [];
  List<String> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final history =
        await widget.auth.chatSearchHistoryFor(widget.conversation.id);
    final msgs = await widget.loader.load();
    if (!mounted) return;
    setState(() {
      _history = history;
      _all = msgs;
      _loading = false;
    });
  }

  List<ChatMessage> get _results {
    final q = _query.text.trim();
    if (q.isEmpty) return const [];
    return _all.where((m) {
      if (m.type == 'system') return false;
      if (textMatchesQuery(m.displayText, q)) return true;
      return textMatchesQuery(_nameFor(m.senderId), q);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  String _nameFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.username;
    return widget.auth.groupMemberUsername(widget.conversation, userId);
  }

  String? _avatarFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.avatarUrl;
    return widget.auth.groupMemberAvatarUrl(widget.conversation, userId);
  }

  Future<void> _submitSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    await widget.auth.addChatSearchHistory(widget.conversation.id, trimmed);
    final history =
        await widget.auth.chatSearchHistoryFor(widget.conversation.id);
    if (!mounted) return;
    setState(() => _history = history);
  }

  void _pickMessage(String id) {
    final q = _query.text.trim();
    if (q.isNotEmpty) unawaited(_submitSearch(q));
    Navigator.of(context).pop(ChatHistoryJump(messageId: id));
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = widget.conversation.type == 'group';
    final q = _query.text.trim();
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索聊天记录',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _submitSearch,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : q.isEmpty
              ? _buildHistory(context)
              : results.isEmpty
                  ? const Center(child: Text('无匹配消息'))
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final msg = results[index];
                        return ChatHistoryResultTile(
                          msg: msg,
                          name: _nameFor(msg.senderId),
                          senderTitle: isGroup
                              ? widget.conversation.memberTitle(msg.senderId)
                              : null,
                          avatarUrl: _avatarFor(msg.senderId),
                          highlightQuery: q,
                          onTap: () => _pickMessage(msg.id),
                        );
                      },
                    ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          '输入关键词搜索名称或聊天内容',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '搜索记录',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        ..._history.map(
          (item) => ListTile(
            leading: const Icon(Icons.history),
            title: Text(item),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () async {
                await widget.auth.removeChatSearchHistoryItem(
                  widget.conversation.id,
                  item,
                );
                final next = await widget.auth.chatSearchHistoryFor(
                  widget.conversation.id,
                );
                if (!mounted) return;
                setState(() => _history = next);
              },
            ),
            onTap: () {
              _query.text = item;
              _query.selection = TextSelection.collapsed(offset: item.length);
              unawaited(_submitSearch(item));
            },
          ),
        ),
      ],
    );
  }
}
