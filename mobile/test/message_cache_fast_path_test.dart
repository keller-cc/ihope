import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/conversation.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/models/user.dart';
import 'package:ihope/services/auth_service.dart';

ChatMessage _msg(String id, String pt) {
  return ChatMessage(
    id: id,
    conversationId: 'c1',
    senderId: 'peer',
    type: 'text',
    ciphertext: 'cipher',
    createdAt: DateTime.utc(2026, 1, 1),
    plaintext: pt,
  );
}

void main() {
  group('message cache fast paths', () {
    late AuthService auth;
    late ConversationItem conv;

    setUp(() {
      auth = AuthService();
      auth.currentUser = User(
        id: 'me',
        email: 'a@test.com',
        username: 'a',
        identityPublicKey: 'k',
      );
      conv = ConversationItem(
        id: 'c1',
        type: 'private',
        members: [
          ConversationMember(userId: 'me', username: 'me'),
          ConversationMember(userId: 'peer', username: 'peer'),
        ],
      );
    });

    test('previewIfCached returns plaintext without decrypt', () {
      final msg = _msg('m1', 'hello');
      expect(auth.previewIfCached(msg), 'hello');
      expect(auth.previewIfCached(_msg('m2', '…')), isNull);
    });

    test('messagesForQuickDisplay uses cached plaintext', () {
      final list = auth.messagesForQuickDisplay(conv, [
        _msg('m1', 'hi'),
        _msg('m2', ''),
      ]);
      expect(list[0].plaintext, 'hi');
      expect(list[1].plaintext, ChatMessage.decryptPlaceholder);
    });
  });
}
