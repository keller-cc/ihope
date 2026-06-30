import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_client.dart';

class ConversationService {
  ConversationService(this.api);

  final ApiClient api;

  Future<List<ConversationItem>> listConversations() async {
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

  Future<List<ChatMessage>> listMessages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) async {
    final data = await api.getJson(
      '/api/conversations/$conversationId/messages',
      query: {
        'limit': limit,
        if (before != null) 'before': before,
      },
    );
    return (data['messages'] as List<dynamic>)
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<ChatMessage> sendMessage(
    String conversationId,
    String text,
  ) async {
    final data = await api.postJson(
      '/api/conversations/$conversationId/messages',
      body: {
        'type': 'text',
        'ciphertext': text,
      },
    );
    return ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
  }
}
