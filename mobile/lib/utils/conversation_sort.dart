import '../models/conversation.dart';

DateTime _activityTime(ConversationItem item) =>
    item.lastMessage?.createdAt.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _compareByActivity(ConversationItem a, ConversationItem b) =>
    _activityTime(b).compareTo(_activityTime(a));

/// 置顶优先；同组内按最后消息时间倒序。
List<ConversationItem> sortConversationsByPin(
  List<ConversationItem> items,
  List<String> pinnedIds,
) {
  if (items.isEmpty) return [];

  final byId = {for (final c in items) c.id: c};
  final pinned = <ConversationItem>[];
  for (final id in pinnedIds) {
    final conv = byId[id];
    if (conv != null) pinned.add(conv);
  }
  pinned.sort(_compareByActivity);

  final unpinned = items.where((c) => !pinnedIds.contains(c.id)).toList()
    ..sort(_compareByActivity);

  return [...pinned, ...unpinned];
}
