import 'message.dart';

class ConversationMember {
  ConversationMember({
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.identityPublicKey = '',
    this.joinedEpoch = 0,
  });

  final String userId;
  final String username;
  final String? avatarUrl;
  final String identityPublicKey;
  final int joinedEpoch;

  factory ConversationMember.fromJson(Map<String, dynamic> json) {
    return ConversationMember(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '?',
      avatarUrl: json['avatar_url'] as String?,
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      joinedEpoch: json['joined_epoch'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'identity_public_key': identityPublicKey,
        'joined_epoch': joinedEpoch,
      };
}

class ConversationItem {
  ConversationItem({
    required this.id,
    required this.type,
    required this.members,
    this.name,
    this.avatarUrl,
    this.lastMessage,
    this.epoch = 0,
    this.ownerId,
    this.isArchived = false,
  });

  final String id;
  final String type;
  final String? name;
  final String? avatarUrl;
  final List<ConversationMember> members;
  final ChatMessage? lastMessage;
  final int epoch;
  final String? ownerId;
  final bool isArchived;

  factory ConversationItem.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List<dynamic>? ?? [])
        .map((e) => ConversationMember.fromJson(e as Map<String, dynamic>))
        .toList();
    final convId = json['id'] as String? ?? '';
    if (convId.isEmpty) {
      throw FormatException('conversation id missing');
    }
    ChatMessage? last;
    final rawLast = json['last_message'];
    if (rawLast is Map<String, dynamic> && rawLast['id'] is String) {
      last = ChatMessage.fromJson({
        ...rawLast,
        'conversation_id': rawLast['conversation_id'] ?? convId,
      });
    }
    return ConversationItem(
      id: convId,
      type: json['type'] as String? ?? 'group',
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      members: members,
      lastMessage: last,
      epoch: json['epoch'] as int? ?? 0,
      ownerId: json['owner_id'] as String?,
      isArchived: json['is_archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'members': members.map((m) => m.toJson()).toList(),
        if (lastMessage != null) 'last_message': lastMessage!.toJson(),
        'epoch': epoch,
        if (ownerId != null) 'owner_id': ownerId,
        'is_archived': isArchived,
      };

  ConversationItem copyWith({
    String? name,
    String? avatarUrl,
    ChatMessage? lastMessage,
    int? epoch,
    List<ConversationMember>? members,
    bool? isArchived,
  }) {
    return ConversationItem(
      id: id,
      type: type,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      members: members ?? this.members,
      lastMessage: lastMessage ?? this.lastMessage,
      epoch: epoch ?? this.epoch,
      ownerId: ownerId,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  bool isOwner(String userId) => ownerId == userId;

  String? memberTitle(String userId) {
    if (type != 'group' || ownerId == null) return null;
    if (userId == ownerId) return '群主';
    return null;
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

  String? displayAvatarUrl(String currentUserId) {
    if (type == 'group') return avatarUrl;
    for (final m in members) {
      if (m.userId != currentUserId) {
        return m.avatarUrl;
      }
    }
    return null;
  }

  int joinedEpochFor(String userId) {
    for (final m in members) {
      if (m.userId == userId) return m.joinedEpoch;
    }
    return 0;
  }

  String peerDisplayName(String currentUserId) => displayTitle(currentUserId);
}
