import '../models/conversation.dart';

/// 按置顶顺序排列会话（置顶 id 在前，其余保持相对顺序）。
List<ConversationItem> sortConversationsByPin(
  List<ConversationItem> items,
  List<String> pinnedIds,
) {
  if (pinnedIds.isEmpty) return List.of(items);

  final byId = {for (final c in items) c.id: c};
  final pinned = <ConversationItem>[];
  for (final id in pinnedIds) {
    final conv = byId[id];
    if (conv != null) pinned.add(conv);
  }
  final unpinned = items.where((c) => !pinnedIds.contains(c.id)).toList();
  return [...pinned, ...unpinned];
}
