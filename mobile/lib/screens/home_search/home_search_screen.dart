import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import 'home_search_category_screen.dart';
import 'home_search_messages_screen.dart';
import 'home_search_models.dart';
import 'home_search_widgets.dart';

/// 首页搜索主界面：联系人 / 群聊 / 聊天记录三块，每块最多预览 3 条。
class HomeSearchScreen extends StatefulWidget {
  const HomeSearchScreen({
    super.key,
    required this.auth,
    required this.conversations,
    required this.messageCache,
    required this.onOpenChat,
  });

  final AuthService auth;
  final List<ConversationItem> conversations;
  final Map<String, List<ChatMessage>> messageCache;
  final HomeSearchOpenChat onOpenChat;

  @override
  State<HomeSearchScreen> createState() => _HomeSearchScreenState();
}

class _HomeSearchScreenState extends State<HomeSearchScreen> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _meId => widget.auth.currentUser!.id;

  HomeSearchResults get _results => HomeSearchEngine.search(
        conversations: widget.conversations,
        messageCache: widget.messageCache,
        meId: _meId,
        query: _query.text,
      );

  Future<void> _openCategory(HomeSearchCategory kind) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HomeSearchCategoryScreen(
          kind: kind,
          auth: widget.auth,
          conversations: widget.conversations,
          messageCache: widget.messageCache,
          initialQuery: _query.text,
          onOpenChat: widget.onOpenChat,
        ),
      ),
    );
  }

  Future<void> _closeSearchAndOpen(
    ConversationItem conversation, {
    String? messageId,
  }) async {
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
            await _closeSearchAndOpen(hit.conversation, messageId: id);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final results = _results;
    final contacts = results.contacts.take(HomeSearchResults.previewLimit).toList();
    final groups = results.groups.take(HomeSearchResults.previewLimit).toList();
    final messages =
        results.messages.take(HomeSearchResults.previewLimit).toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '搜索',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          ),
          textInputAction: TextInputAction.search,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
      body: q.isEmpty
          ? Center(
              child: Text(
                '搜索联系人、群聊或聊天记录',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          : ListView(
              children: [
                if (contacts.isNotEmpty)
                  HomeSearchSection(
                    title: '联系人',
                    onMore: results.contacts.isNotEmpty
                        ? () => _openCategory(HomeSearchCategory.contacts)
                        : null,
                    child: Column(
                      children: contacts
                          .map(
                            (h) => HomeSearchContactTile(
                              conversation: h.conversation,
                              meId: _meId,
                              onTap: () => _closeSearchAndOpen(h.conversation),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (groups.isNotEmpty)
                  HomeSearchSection(
                    title: '群聊',
                    onMore: results.groups.isNotEmpty
                        ? () => _openCategory(HomeSearchCategory.groups)
                        : null,
                    child: Column(
                      children: groups
                          .map(
                            (h) => HomeSearchGroupTile(
                              hit: h,
                              meId: _meId,
                              onTap: () => _closeSearchAndOpen(h.conversation),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (messages.isNotEmpty)
                  HomeSearchSection(
                    title: '聊天记录',
                    onMore: results.messages.isNotEmpty
                        ? () => _openCategory(HomeSearchCategory.messages)
                        : null,
                    child: Column(
                      children: messages
                          .map(
                            (h) => HomeSearchMessageTile(
                              hit: h,
                              meId: _meId,
                              query: q,
                              onTap: () => _openMessageHit(h),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                if (contacts.isEmpty && groups.isEmpty && messages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('无匹配结果')),
                  ),
              ],
            ),
    );
  }
}
