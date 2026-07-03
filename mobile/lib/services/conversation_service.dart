import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_client.dart';

class ConversationService {
  ConversationService(this.api);

  final ApiClient api;
  Future<List<ConversationItem>>? _listInFlight;

  Future<List<ConversationItem>> listConversations() {
    final inFlight = _listInFlight;
    if (inFlight != null) return inFlight;

    final task = _fetchConversations();
    _listInFlight = task;
    return task.whenComplete(() {
      if (identical(_listInFlight, task)) {
        _listInFlight = null;
      }
    });
  }

  Future<List<ConversationItem>> _fetchConversations() async {
    final data = await api.getJson('/api/conversations');
    return (data['conversations'] as List<dynamic>)
        .map((e) => ConversationItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PublicUser>> listUsers({String? query}) async {
    final data = await api.getJson('/api/users', query: {
      if (query != null && query.isNotEmpty) 'q': query,
    });
    return (data['users'] as List<dynamic>)
        .map((e) => PublicUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ConversationItem> createPrivateChat(String peerUserId) async {
    final data = await api.postJson('/api/conversations', body: {
      'type': 'private',
      'peer_user_id': peerUserId,
    });
    return ConversationItem.fromJson(
      data['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ConversationItem> createGroupChat({
    required String name,
    required List<String> memberIds,
  }) async {
    final data = await api.postJson('/api/conversations', body: {
      'type': 'group',
      'name': name,
      'member_ids': memberIds,
    });
    return ConversationItem.fromJson(
      data['conversation'] as Map<String, dynamic>,
    );
  }

  Future<({ConversationItem conversation, int epoch})> addMembers(
    String conversationId,
    List<String> memberIds,
  ) async {
    final data = await api.postJson(
      '/api/conversations/$conversationId/members',
      body: {'member_ids': memberIds},
    );
    return (
      conversation: ConversationItem.fromJson(
        data['conversation'] as Map<String, dynamic>,
      ),
      epoch: data['epoch'] as int,
    );
  }

  /// Megolm 定期轮换：epoch+1，不改变成员 joined_epoch。
  Future<({ConversationItem conversation, int epoch})> rotateGroupKeys(
    String conversationId,
  ) async {
    final data = await api.postJson(
      '/api/conversations/$conversationId/rotate-keys',
    );
    return (
      conversation: ConversationItem.fromJson(
        data['conversation'] as Map<String, dynamic>,
      ),
      epoch: data['epoch'] as int,
    );
  }

  Future<
      ({
        ConversationItem conversation,
        int epoch,
        ChatMessage? systemMessage,
      })> removeMember(
    String conversationId,
    String userId,
  ) async {
    final data = await api.deleteJson(
      '/api/conversations/$conversationId/members/$userId',
    );
    ChatMessage? systemMessage;
    final rawSys = data['system_message'];
    if (rawSys is Map<String, dynamic>) {
      systemMessage = ChatMessage.fromJson(rawSys);
    }
    return (
      conversation: ConversationItem.fromJson(
        data['conversation'] as Map<String, dynamic>,
      ),
      epoch: data['epoch'] as int,
      systemMessage: systemMessage,
    );
  }

  Future<void> dissolveGroup(String conversationId) async {
    await api.deleteJson('/api/conversations/$conversationId');
  }

  Future<ConversationItem> updateGroupName(
    String conversationId,
    String name,
  ) async {
    final data = await api.patchJson(
      '/api/conversations/$conversationId',
      body: {'name': name.trim()},
    );
    return ConversationItem.fromJson(
      data['conversation'] as Map<String, dynamic>,
    );
  }

  Future<ConversationItem> uploadGroupAvatar(
    String conversationId,
    List<int> bytes, {
    String filename = 'avatar.jpg',
  }) async {
    final data = await api.postMultipart(
      '/api/conversations/$conversationId/avatar',
      field: 'avatar',
      filename: filename,
      bytes: bytes,
    );
    return ConversationItem.fromJson(
      data['conversation'] as Map<String, dynamic>,
    );
  }

  Future<void> uploadKeyBundles(
    String conversationId,
    List<Map<String, dynamic>> bundles,
  ) async {
    await api.postJson(
      '/api/conversations/$conversationId/key-bundles',
      body: {'bundles': bundles},
    );
  }

  Future<List<GroupKeyBundle>> fetchKeyBundles(
    String conversationId, {
    List<int>? epochs,
  }) async {
    final data = await api.getJson(
      '/api/conversations/$conversationId/key-bundles',
      query: {
        if (epochs != null && epochs.isNotEmpty)
          'epochs': epochs.map((e) => e.toString()).join(','),
      },
    );
    return (data['bundles'] as List<dynamic>? ?? [])
        .map((e) => GroupKeyBundle.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ConversationMember>> listMemberDirectory(
    String conversationId,
  ) async {
    final data = await api.getJson(
      '/api/conversations/$conversationId/member-directory',
    );
    return (data['members'] as List<dynamic>)
        .map((e) => ConversationMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> listMessages(
    String conversationId, {
    int limit = 50,
    String? before,
    String? type,
  }) async {
    final data = await api.getJson(
      '/api/conversations/$conversationId/messages',
      query: {
        'limit': limit,
        if (before != null) 'before': before,
        if (type != null) 'type': type,
      },
    );
    return (data['messages'] as List<dynamic>)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<ChatMessage> sendMessage(
    String conversationId,
    String ciphertext, {
    String type = 'text',
  }) async {
    final isMedia = type == 'audio' || type == 'image' || type == 'file';
    final data = await api.postJson(
      '/api/conversations/$conversationId/messages',
      body: {
        'type': type,
        'ciphertext': ciphertext,
      },
      receiveTimeout: isMedia ? const Duration(seconds: 120) : null,
      sendTimeout: isMedia ? const Duration(seconds: 120) : null,
    );
    return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
  }
}

class GroupKeyBundle {
  GroupKeyBundle({
    required this.epoch,
    required this.senderId,
    required this.ciphertext,
  });

  final int epoch;
  final String senderId;
  final String ciphertext;

  factory GroupKeyBundle.fromJson(Map<String, dynamic> json) {
    return GroupKeyBundle(
      epoch: json['epoch'] as int,
      senderId: json['sender_id'] as String,
      ciphertext: json['ciphertext'] as String,
    );
  }
}
