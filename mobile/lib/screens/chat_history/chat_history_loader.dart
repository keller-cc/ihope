import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';

/// 加载本机会话消息供查找功能使用。
class ChatHistoryLoader {
  ChatHistoryLoader({
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  List<ChatMessage>? _cache;

  List<ChatMessage> get messages => _cache ?? const [];

  Future<List<ChatMessage>> load() async {
    if (_cache != null) return _cache!;
    if (conversation.type == 'group') {
      await auth.ensureGroupMemberDirectory(conversation);
    }
    final msgs = await auth.loadLocalMessagesForSearch(conversation);
    final me = auth.currentUser;
    if (me != null) {
      _cache = conversation.messagesVisibleToMember(me.id, msgs);
    } else {
      _cache = msgs;
    }
    return _cache!;
  }

  /// 选中日期当天 00:00 起，最近的一条消息（含当天首条）。
  static ChatMessage? nearestOnOrAfter(List<ChatMessage> messages, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    ChatMessage? best;
    for (final m in messages) {
      if (m.createdAt.isBefore(start)) continue;
      if (best == null || m.createdAt.isBefore(best.createdAt)) best = m;
    }
    return best;
  }

  static List<ChatMessage> filterBySender(
    List<ChatMessage> messages,
    String senderId,
  ) {
    return messages.where((m) => m.senderId == senderId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static List<ChatMessage> filterImages(List<ChatMessage> messages) {
    return messages.where((m) => m.type == 'image').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static List<ChatMessage> filterFiles(List<ChatMessage> messages) {
    return messages.where((m) => m.type == 'file').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  static Map<String, List<ChatMessage>> groupByYearMonth(
    List<ChatMessage> messages,
  ) {
    final map = <String, List<ChatMessage>>{};
    for (final m in messages) {
      final t = m.createdAt.toLocal();
      final key = '${t.year}年${t.month}月';
      map.putIfAbsent(key, () => []).add(m);
    }
    return map;
  }
}
