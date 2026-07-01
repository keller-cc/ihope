import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/screens/chat/chat_thread_loader.dart';

ChatMessage _msg(String id, DateTime at, {String? plaintext}) {
  return ChatMessage(
    id: id,
    conversationId: 'conv-1',
    senderId: 'alice',
    type: 'text',
    ciphertext: 'cipher-$id',
    createdAt: at,
    plaintext: plaintext,
  );
}

void main() {
  group('ChatThreadLoader.merge', () {
    test('merges cached plaintext into remote messages', () {
      final t1 = DateTime(2026, 1, 1, 10);
      final t2 = DateTime(2026, 1, 1, 11);
      final remote = [
        _msg('a', t1),
        _msg('b', t2),
      ];
      final cached = [
        _msg('a', t1, plaintext: 'hello'),
      ];

      final merged = ChatThreadLoader.merge(remote, cached);
      expect(merged.length, 2);
      expect(merged[0].id, 'a');
      expect(merged[0].plaintext, 'hello');
      expect(merged[1].id, 'b');
    });

    test('adds cached-only messages and sorts by createdAt', () {
      final t1 = DateTime(2026, 1, 1, 10);
      final t2 = DateTime(2026, 1, 1, 12);
      final t3 = DateTime(2026, 1, 1, 11);
      final remote = [_msg('a', t1)];
      final cached = [
        _msg('c', t3, plaintext: 'middle'),
        _msg('b', t2, plaintext: 'last'),
      ];

      final merged = ChatThreadLoader.merge(remote, cached);
      expect(merged.map((m) => m.id).toList(), ['a', 'c', 'b']);
    });

    test('ignores empty cached plaintext', () {
      final t1 = DateTime(2026, 1, 1, 10);
      final remote = [_msg('a', t1, plaintext: 'remote')];
      final cached = [_msg('a', t1, plaintext: '')];

      final merged = ChatThreadLoader.merge(remote, cached);
      expect(merged.single.plaintext, 'remote');
    });
  });

  group('ChatThreadLoader.upsert', () {
    test('appends new message', () {
      final t1 = DateTime(2026, 1, 1, 10);
      final existing = [_msg('a', t1)];
      final added = _msg('b', t1.add(const Duration(minutes: 1)));

      final out = ChatThreadLoader.upsert(existing, added);
      expect(out.length, 2);
      expect(out.last.id, 'b');
    });

    test('replaces message with same id', () {
      final t1 = DateTime(2026, 1, 1, 10);
      final existing = [
        _msg('a', t1),
        _msg('b', t1.add(const Duration(minutes: 1)), plaintext: 'old'),
      ];
      final updated = _msg('b', t1.add(const Duration(minutes: 1)), plaintext: 'new');

      final out = ChatThreadLoader.upsert(existing, updated);
      expect(out.length, 2);
      expect(out[1].plaintext, 'new');
    });
  });
}
