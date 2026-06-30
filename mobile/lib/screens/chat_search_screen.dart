import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../utils/message_time.dart';
import '../utils/text_search.dart';
import '../widgets/chat_bubble.dart';

/// 在本机持久化数据中搜索，不请求后端。
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _query = TextEditingController();
  List<ChatMessage> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
    _loadLocalMessages();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadLocalMessages() async {
    setState(() => _loading = true);
    final msgs = await widget.auth.loadLocalMessagesForSearch(
      widget.conversation,
    );
    if (!mounted) return;
    setState(() {
      _all = msgs;
      _loading = false;
    });
  }

  List<ChatMessage> get _results {
    final q = _query.text.trim();
    if (q.isEmpty) return const [];
    return _all.where((m) {
      if (textMatchesQuery(m.displayText, q)) return true;
      return textMatchesQuery(_nameFor(m.senderId), q);
    }).toList();
  }

  String _nameFor(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.username;
    for (final m in widget.conversation.members) {
      if (m.userId == userId) return m.username;
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    final isGroup = widget.conversation.type == 'group';
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索聊天记录'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索本机聊天记录',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _query.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _loading
                    ? '正在读取本机数据…'
                    : '共 ${_all.length} 条本机消息 · 不联网搜索',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _query.text.trim().isEmpty
                    ? Center(
                        child: Text(
                          '输入关键词搜索',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    : results.isEmpty
                        ? const Center(child: Text('无匹配消息'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final msg = results[index];
                              final prev =
                                  index > 0 ? results[index - 1] : null;
                              return _buildItem(
                                context,
                                me,
                                msg,
                                prev,
                                isGroup,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    User me,
    ChatMessage msg,
    ChatMessage? prev,
    bool isGroup,
  ) {
    final showTime = MessageTimeFormat.shouldShowDivider(
      prev?.createdAt,
      msg.createdAt,
    );
    if (msg.type == 'system') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTime)
            MessageTimeDivider(
              label: MessageTimeFormat.formatDivider(msg.createdAt),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                msg.displayText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTime)
          MessageTimeDivider(
            label: MessageTimeFormat.formatDivider(msg.createdAt),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ChatBubble(
            msg: msg,
            mine: msg.senderId == me.id,
            isGroup: isGroup,
            me: me,
            senderTitle: widget.conversation.memberTitle(msg.senderId),
            nameFor: _nameFor,
            avatarUrlFor: (id) {
              if (id == me.id) return me.avatarUrl;
              for (final m in widget.conversation.members) {
                if (m.userId == id) return m.avatarUrl;
              }
              return null;
            },
            onPeerTap: (_) {},
          ),
        ),
      ],
    );
  }
}
