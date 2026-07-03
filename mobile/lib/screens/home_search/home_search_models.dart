import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../utils/media_payload.dart';
import '../../utils/text_search.dart';

typedef HomeSearchOpenChat = Future<void> Function(
  ConversationItem conversation, {
  String? messageId,
});

/// 首页搜索：联系人命中。
class HomeSearchContactHit {
  const HomeSearchContactHit({required this.conversation});

  final ConversationItem conversation;
}

/// 首页搜索：群聊命中（[matchedMemberName] 非空表示因成员命中）。
class HomeSearchGroupHit {
  const HomeSearchGroupHit({
    required this.conversation,
    this.matchedMemberName,
  });

  final ConversationItem conversation;
  final String? matchedMemberName;
}

/// 首页搜索：会话内消息命中。
class HomeSearchMessageHit {
  const HomeSearchMessageHit({
    required this.conversation,
    required this.messages,
  });

  final ConversationItem conversation;
  final List<ChatMessage> messages;
}

class HomeSearchResults {
  const HomeSearchResults({
    required this.contacts,
    required this.groups,
    required this.messages,
  });

  final List<HomeSearchContactHit> contacts;
  final List<HomeSearchGroupHit> groups;
  final List<HomeSearchMessageHit> messages;

  static const previewLimit = 3;
}

/// 首页本地搜索（会话元数据 + 本机消息缓存）。
class HomeSearchEngine {
  HomeSearchEngine._();

  static HomeSearchResults search({
    required List<ConversationItem> conversations,
    required Map<String, List<ChatMessage>> messageCache,
    required String meId,
    required String query,
  }) {
    final q = query.trim();
    if (q.isEmpty) {
      return const HomeSearchResults(
        contacts: [],
        groups: [],
        messages: [],
      );
    }

    return HomeSearchResults(
      contacts: _searchContacts(conversations, meId, q),
      groups: _searchGroups(conversations, meId, q),
      messages: _searchMessages(conversations, messageCache, meId, q),
    );
  }

  static List<HomeSearchContactHit> _searchContacts(
    List<ConversationItem> conversations,
    String meId,
    String q,
  ) {
    final hits = <HomeSearchContactHit>[];
    for (final c in conversations) {
      if (c.type == 'group' || c.isArchived) continue;
      if (textMatchesQuery(c.displayTitle(meId), q)) {
        hits.add(HomeSearchContactHit(conversation: c));
      }
    }
    hits.sort(
      (a, b) => a.conversation
          .displayTitle(meId)
          .compareTo(b.conversation.displayTitle(meId)),
    );
    return hits;
  }

  static List<HomeSearchGroupHit> _searchGroups(
    List<ConversationItem> conversations,
    String meId,
    String q,
  ) {
    final hits = <HomeSearchGroupHit>[];
    for (final c in conversations) {
      if (c.type != 'group' || c.isArchived) continue;
      final title = c.displayTitle(meId);
      final nameMatch = textMatchesQuery(title, q);
      final memberHits = c.members
          .where((m) => m.userId != meId && textMatchesQuery(m.username, q))
          .toList();

      if (!nameMatch && memberHits.isEmpty) continue;

      if (memberHits.isNotEmpty) {
        for (final m in memberHits) {
          hits.add(
            HomeSearchGroupHit(
              conversation: c,
              matchedMemberName: m.username,
            ),
          );
        }
      } else {
        hits.add(HomeSearchGroupHit(conversation: c));
      }
    }
    return hits;
  }

  static List<HomeSearchMessageHit> _searchMessages(
    List<ConversationItem> conversations,
    Map<String, List<ChatMessage>> messageCache,
    String meId,
    String q,
  ) {
    final hits = <HomeSearchMessageHit>[];
    for (final c in conversations) {
      if (c.isArchived) continue;
      final cached = messageCache[c.id];
      if (cached == null || cached.isEmpty) continue;
      final matched = <ChatMessage>[];
      for (final m in cached) {
        if (m.type == 'system') continue;
        final text = _messageSearchText(m);
        if (textMatchesQuery(text, q)) {
          matched.add(m);
        }
      }
      if (matched.isEmpty) continue;
      matched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      hits.add(HomeSearchMessageHit(conversation: c, messages: matched));
    }
    hits.sort(
      (a, b) => b.messages.first.createdAt
          .compareTo(a.messages.first.createdAt),
    );
    return hits;
  }

  static String _messageSearchText(ChatMessage m) {
    if (m.type == 'text' || m.type == 'announcement') return m.displayText;
    return MediaPayload.previewFromPlaintext(m.plaintext, m.type);
  }
}
