import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import 'home_search_messages_screen.dart';
import 'home_search_models.dart';
import 'home_search_widgets.dart';

enum HomeSearchCategory { contacts, groups, messages }

/// 某一类搜索的完整结果页。
class HomeSearchCategoryScreen extends StatefulWidget {
  const HomeSearchCategoryScreen({
    super.key,
    required this.kind,
    required this.auth,
    required this.conversations,
    required this.messageCache,
    required this.onOpenChat,
    this.initialQuery = '',
  });

  final HomeSearchCategory kind;
  final AuthService auth;
  final List<ConversationItem> conversations;
  final Map<String, List<ChatMessage>> messageCache;
  final HomeSearchOpenChat onOpenChat;
  final String initialQuery;

  @override
  State<HomeSearchCategoryScreen> createState() =>
      _HomeSearchCategoryScreenState();
}

class _HomeSearchCategoryScreenState extends State<HomeSearchCategoryScreen> {
  late final TextEditingController _query;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.initialQuery);
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _meId => widget.auth.currentUser!.id;

  String get _title => switch (widget.kind) {
        HomeSearchCategory.contacts => '联系人',
        HomeSearchCategory.groups => '群聊',
        HomeSearchCategory.messages => '聊天记录',
      };

  HomeSearchResults get _results => HomeSearchEngine.search(
        conversations: widget.conversations,
        messageCache: widget.messageCache,
        meId: _meId,
        query: _query.text,
      );

  Future<void> _closeSearchAndOpen(
    ConversationItem conversation, {
    String? messageId,
  }) async {
    Navigator.of(context).pop();
    Navigator.of(context).pop();
    await widget.onOpenChat(conversation, messageId: messageId);
  }

  Future<void> _openMessageHit(HomeSearchMessageHit hit) async {
    if (hit.messages.length == 1) {
      await _closeSearchAndOpen(
        hit.conversation,
        messageId: hit.messages.first.id,
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HomeSearchMessagesScreen(
          conversation: hit.conversation,
          messages: hit.messages,
          meId: _meId,
          query: _query.text,
          onOpenMessage: (id) async {
            Navigator.of(context).pop();
            Navigator.of(context).pop();
            Navigator.of(context).pop();
            await widget.onOpenChat(hit.conversation, messageId: id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final results = _results;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          decoration: InputDecoration(
            hintText: '搜索$_title',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
      body: q.isEmpty
          ? const Center(child: Text('输入关键词搜索'))
          : ListView(
              children: [
                if (widget.kind == HomeSearchCategory.contacts)
                  ...results.contacts.map(
                    (h) => HomeSearchContactTile(
                      conversation: h.conversation,
                      meId: _meId,
                      onTap: () => _closeSearchAndOpen(h.conversation),
                    ),
                  ),
                if (widget.kind == HomeSearchCategory.groups)
                  ...results.groups.map(
                    (h) => HomeSearchGroupTile(
                      hit: h,
                      meId: _meId,
                      onTap: () => _closeSearchAndOpen(h.conversation),
                    ),
                  ),
                if (widget.kind == HomeSearchCategory.messages)
                  ...results.messages.map(
                    (h) => HomeSearchMessageTile(
                      hit: h,
                      meId: _meId,
                      query: q,
                      onTap: () => _openMessageHit(h),
                    ),
                  ),
              ],
            ),
    );
  }
}
