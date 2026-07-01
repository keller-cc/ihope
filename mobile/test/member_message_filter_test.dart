import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/conversation.dart';
import 'package:ihope/models/message.dart';

ChatMessage _msg(String id, int epoch, {String type = 'text'}) {
  return ChatMessage(
    id: id,
    conversationId: 'g1',
    senderId: 'other',
    type: type,
    ciphertext: 'cipher',
    epoch: epoch,
    createdAt: DateTime.utc(2026, 1, epoch + 1),
  );
}

ConversationItem _group({required int bobJoinedEpoch, bool archived = false}) {
  return ConversationItem(
    id: 'g1',
    type: 'group',
    name: 'G',
    members: [
      ConversationMember(userId: 'bob', username: 'Bob', joinedEpoch: bobJoinedEpoch),
      ConversationMember(userId: 'tom', username: 'Tom', joinedEpoch: 0),
    ],
    isArchived: archived,
  );
}

void main() {
  test('active member only sees current joined_epoch messages', () {
    final conv = _group(bobJoinedEpoch: 3);
    final filtered = conv.messagesVisibleToMember('bob', [
      _msg('kick', 2, type: 'system'),
      _msg('join', 3, type: 'system'),
      _msg('chat', 3),
    ]);
    expect(filtered.map((m) => m.id), ['join', 'chat']);
  });

  test('archived conversation keeps full local history', () {
    final conv = _group(bobJoinedEpoch: 3, archived: true);
    final filtered = conv.messagesVisibleToMember('bob', [
      _msg('kick', 2, type: 'system'),
      _msg('join', 3, type: 'system'),
    ]);
    expect(filtered.length, 2);
  });
}
