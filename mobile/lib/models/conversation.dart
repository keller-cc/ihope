import 'message.dart';

class ConversationMember {
  ConversationMember({
    required this.userId,
    required this.username,
  });

  final String userId;
  final String username;

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      userId: json['user_id'] as String,
      username: json['username'] as String,
    );
  }
}

class ConversationItem {
  ConversationItem({
    required this.id,
    required this.type,
    required this.members,
    this.name,
    this.lastMessage,
  });

  final String id;
  final String type;
  final String? name;
  final List<ConversationMember> members;
  final ChatMessage? lastMessage;

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>? ?? [])
        .map((e) => ConversationMember.fromJson(e as Map<String, dynamic>))
        .toList();
    final convId = json['id'] as String;
    ChatMessage? last;
    final rawLast = json['last_message'];
    if (rawLast is Map<String, dynamic>) {
      last = ChatMessage.fromJson({
        ...rawLast,
        'conversation_id': rawLast['conversation_id'] ?? convId,
      });
    }
    return ConversationItem(
      id: convId,
      type: json['type'] as String,
      name: json['name'] as String?,
      members: members,
      lastMessage: last,
    );
  }

  String displayTitle(String currentUserId) {
    if (type == 'group' && name != null && name!.isNotEmpty) {
      return name!;
    }
    for (final m in members) {
      if (m.userId != currentUserId) {
        return m.username;
      }
    }
    return 'Chat';
  }
}
