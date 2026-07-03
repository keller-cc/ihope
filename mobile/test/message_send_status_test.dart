import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/screens/chat/chat_thread_loader.dart';

void main() {
  group('ChatMessage send status', () {
    test('local outgoing ids use prefix and are not cacheable', () {
      final id = ChatMessage.newLocalId();
      expect(id.startsWith(ChatMessage.localIdPrefix), isTrue);
      expect(ChatMessage.isLocalId(id), isTrue);

      final msg = ChatMessage(
        id: id,
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: '',
        createdAt: DateTime.utc(2026, 1, 1),
        plaintext: 'hello',
        sendStatus: MessageSendStatus.sending,
      );
      expect(msg.isLocalOutgoing, isTrue);
      expect(msg.isPendingOutgoing, isTrue);
      expect(msg.isCacheable, isFalse);
    });

    test('server messages default to sent and cacheable', () {
      final msg = ChatMessage(
        id: 'server-id',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: 'cipher',
        createdAt: DateTime.utc(2026, 1, 1),
        plaintext: 'hello',
      );
      expect(msg.sendStatus, MessageSendStatus.sent);
      expect(msg.isCacheable, isTrue);
    });

    test('failed local messages stay pending and not cacheable', () {
      final msg = ChatMessage(
        id: ChatMessage.newLocalId(),
        conversationId: 'c1',
        senderId: 'u1',
        type: 'text',
        ciphertext: '',
        createdAt: DateTime.utc(2026, 1, 1),
        plaintext: 'retry me',
        sendStatus: MessageSendStatus.failed,
      );
      expect(msg.isPendingOutgoing, isTrue);
      expect(msg.isCacheable, isFalse);
    });
  });

  group('ChatThreadLoader.preserveLocalOutgoing', () {
    ChatMessage local(String id, MessageSendStatus status) => ChatMessage(
          id: id,
          conversationId: 'c1',
          senderId: 'u1',
          type: 'text',
          ciphertext: '',
          createdAt: DateTime.utc(2026, 1, 1, 12, id.hashCode % 60),
          plaintext: id,
          sendStatus: status,
        );

    ChatMessage server(String id) => ChatMessage(
          id: id,
          conversationId: 'c1',
          senderId: 'u2',
          type: 'text',
          ciphertext: 'x',
          createdAt: DateTime.utc(2026, 1, 1, 10),
          plaintext: id,
        );

    test('keeps sending and failed local messages after history merge', () {
      final pending = local('${ChatMessage.localIdPrefix}1', MessageSendStatus.sending);
      final failed = local('${ChatMessage.localIdPrefix}2', MessageSendStatus.failed);
      final current = [server('s1'), pending, failed];
      final fresh = [server('s1'), server('s2')];

      final merged = ChatThreadLoader.preserveLocalOutgoing(fresh, current);

      expect(merged.map((m) => m.id), containsAll(['s1', 's2', pending.id, failed.id]));
      expect(merged.length, 4);
    });

    test('drops delivered local placeholders from current thread', () {
      final delivered = local('${ChatMessage.localIdPrefix}9', MessageSendStatus.sent);
      final current = [delivered];
      final fresh = [server('s1')];

      final merged = ChatThreadLoader.preserveLocalOutgoing(fresh, current);
      expect(merged.map((m) => m.id), ['s1']);
    });

    test('keeps server message not yet in fresh history during sync race', () {
      final justSent = server('s2');
      final current = [server('s1'), justSent];
      final fresh = [server('s1')];

      final merged = ChatThreadLoader.preserveLocalOutgoing(fresh, current);

      expect(merged.map((m) => m.id), ['s1', 's2']);
    });
  });
}
