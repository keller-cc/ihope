import '../models/message.dart';

/// 群公告已读游标（与聊天消息 readAt 独立）。
class AnnouncementRead {
  AnnouncementRead._();

  static List<ChatMessage> allOf(Iterable<ChatMessage> messages) {
    final list =
        messages.where((m) => m.type == 'announcement').toList(growable: false);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static ChatMessage? latestOf(Iterable<ChatMessage> messages) {
    final all = allOf(messages);
    return all.isEmpty ? null : all.first;
  }

  static ChatMessage? findById(Iterable<ChatMessage> messages, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 某条公告是否未读（按已读 ID 集合，逐条独立标记）。
  static bool isItemUnread({
    required ChatMessage announcement,
    required Set<String> readIds,
    required String myUserId,
  }) {
    return !readIds.contains(announcement.id);
  }

  static bool isUnread({
    required ChatMessage? announcement,
    required Set<String> readIds,
    required String myUserId,
    Iterable<ChatMessage> allMessages = const [],
  }) {
    if (announcement == null) return false;
    return isItemUnread(
      announcement: announcement,
      readIds: readIds,
      myUserId: myUserId,
    );
  }

  static int countUnread(
    Iterable<ChatMessage> messages, {
    required Set<String> readIds,
    required String myUserId,
  }) {
    var n = 0;
    for (final m in allOf(messages)) {
      if (isItemUnread(
        announcement: m,
        readIds: readIds,
        myUserId: myUserId,
      )) {
        n++;
      }
    }
    return n;
  }

  /// 未读公告（新 → 旧）。
  static List<ChatMessage> unreadList(
    Iterable<ChatMessage> messages, {
    required Set<String> readIds,
    required String myUserId,
  }) {
    return allOf(messages)
        .where(
          (m) => isItemUnread(
            announcement: m,
            readIds: readIds,
            myUserId: myUserId,
          ),
        )
        .toList(growable: false);
  }
}
