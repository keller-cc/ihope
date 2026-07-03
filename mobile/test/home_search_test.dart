import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/conversation.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/screens/home_search/home_search_models.dart';

void main() {
  test('HomeSearchEngine finds contacts groups and messages', () {
    final me = 'me';
    final peer = ConversationMember(userId: 'p1', username: 'Alice');
    final dm = ConversationItem(
      id: 'dm1',
      type: 'direct',
      members: [
        ConversationMember(userId: me, username: 'Me'),
        peer,
      ],
    );
    final group = ConversationItem(
      id: 'g1',
      type: 'group',
      name: 'Dev Team',
      members: [
        ConversationMember(userId: me, username: 'Me'),
        ConversationMember(userId: 'p2', username: 'Bob'),
      ],
    );
    final msg = ChatMessage(
      id: 'm1',
      conversationId: 'dm1',
      senderId: 'p1',
      type: 'text',
      ciphertext: 'c',
      createdAt: DateTime(2026, 1, 1),
      plaintext: 'hello keyword world',
    );

    final results = HomeSearchEngine.search(
      conversations: [dm, group],
      messageCache: {'dm1': [msg]},
      meId: me,
      query: 'alice',
    );
    expect(results.contacts.length, 1);

    final groupHit = HomeSearchEngine.search(
      conversations: [dm, group],
      messageCache: const {},
      meId: me,
      query: 'bob',
    );
    expect(groupHit.groups.length, 1);
    expect(groupHit.groups.first.matchedMemberName, 'Bob');

    final msgHit = HomeSearchEngine.search(
      conversations: [dm, group],
      messageCache: {'dm1': [msg]},
      meId: me,
      query: 'keyword',
    );
    expect(msgHit.messages.length, 1);
    expect(msgHit.messages.first.messages.length, 1);
  });
}
