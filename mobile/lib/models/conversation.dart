import 'message.dart';

class ConversationMember {
  ConversationMember({
    required this.userId,
    required this.username,
    this.avatarUrl,
  });

  final String userId;
  final String username;
  final String? avatarUrl;

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      userId: json['user_id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
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

  ConversationItem copyWith({ChatMessage? lastMessage}) {
    return ConversationItem(
      id: id,
      type: type,
      name: name,
      members: members,
      lastMessage: lastMessage ?? this.lastMessage,
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

  /// 单聊对方头像；群聊暂返回 null（后续可扩展群头像）。
  String? peerAvatarUrl(String currentUserId) {
    if (type == 'group') return null;
    for (final m in members) {
      if (m.userId != currentUserId) {
        return m.avatarUrl;
      }
    }
    return null;
  }

  String peerDisplayName(String currentUserId) => displayTitle(currentUserId);
}
