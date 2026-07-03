import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/screens/chat_history/chat_history_loader.dart';

void main() {
  test('nearestOnOrAfter picks first message on or after selected day', () {
    final messages = [
      ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: 'c',
        createdAt: DateTime(2026, 3, 10, 18, 0),
        plaintext: 'day before',
      ),
      ChatMessage(
        id: 'm2',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: 'c',
        createdAt: DateTime(2026, 3, 15, 9, 30),
        plaintext: 'morning',
      ),
      ChatMessage(
        id: 'm3',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: 'c',
        createdAt: DateTime(2026, 3, 15, 20, 0),
        plaintext: 'evening',
      ),
      ChatMessage(
        id: 'm4',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: 'c',
        createdAt: DateTime(2026, 3, 20, 12, 0),
        plaintext: 'later',
      ),
    ];

    final onDay = ChatHistoryLoader.nearestOnOrAfter(
      messages,
      DateTime(2026, 3, 15),
    );
    expect(onDay?.id, 'm2');

    final afterDay = ChatHistoryLoader.nearestOnOrAfter(
      messages,
      DateTime(2026, 3, 16),
    );
    expect(afterDay?.id, 'm4');

    final none = ChatHistoryLoader.nearestOnOrAfter(
      messages,
      DateTime(2026, 4, 1),
    );
    expect(none, isNull);
  });
}
