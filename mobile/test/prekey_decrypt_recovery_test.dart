import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/conversation.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/models/user.dart';
import 'package:ihope/services/auth_service.dart';

ChatMessage _peerText(String id, String ciphertext) {
  return ChatMessage(
    id: id,
    conversationId: 'c1',
    senderId: 'peer',
    type: 'text',
    ciphertext: ciphertext,
    createdAt: DateTime.utc(2026, 7, 4),
  );
}

void main() {
  test('decryptMessagesLocal keeps cached plaintext after decrypt failure', () async {
    final auth = AuthService();
    auth.currentUser = User(
      id: 'me',
      email: 'a@test.com',
      username: 'a',
      identityPublicKey: 'k',
    );
    final conv = ConversationItem(
      id: 'c1',
      type: 'private',
      members: [
        ConversationMember(userId: 'me', username: 'me'),
        ConversationMember(userId: 'peer', username: 'peer'),
      ],
    );

    final cached = _peerText('m1', 'e2ee:sig:{"t":3,"b":"abc"}').copyWith(
      plaintext: '你好',
    );
    await auth.cacheDecryptedMessages('c1', [cached]);

    final incoming = _peerText('m1', 'e2ee:sig:{"t":3,"b":"abc"}').copyWith(
      plaintext: '[无法解密]',
    );
    final out = await auth.decryptMessagesLocal(conv, [incoming]);
    expect(out.single.plaintext, '你好');
  });
}
