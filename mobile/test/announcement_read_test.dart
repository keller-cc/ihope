import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/utils/announcement_read.dart';

ChatMessage _ann(String id, DateTime at, {String sender = 'other'}) {
  return ChatMessage(
    id: id,
    conversationId: 'c1',
    senderId: sender,
    type: 'announcement',
    ciphertext: 'cipher',
    createdAt: at,
    plaintext: 'body',
  );
}

void main() {
  group('AnnouncementRead', () {
    test('latestOf picks newest announcement', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final latest = AnnouncementRead.latestOf([
        _ann('a1', t0),
        ChatMessage(
          id: 't1',
          conversationId: 'c1',
          senderId: 'x',
          type: 'text',
          ciphertext: '',
          createdAt: t0.add(const Duration(hours: 1)),
        ),
        _ann('a2', t0.add(const Duration(hours: 2))),
      ]);
      expect(latest?.id, 'a2');
    });

    test('isUnread when read marker is older announcement', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final t1 = t0.add(const Duration(hours: 1));
      final all = [_ann('a1', t0), _ann('a2', t1)];
      expect(
        AnnouncementRead.isUnread(
          announcement: all[1],
          readMessageId: 'a1',
          myUserId: 'me',
          allMessages: all,
        ),
        isTrue,
      );
      expect(
        AnnouncementRead.isUnread(
          announcement: all[1],
          readMessageId: 'a2',
          myUserId: 'me',
          allMessages: all,
        ),
        isFalse,
      );
    });

    test('countUnread across history', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final all = [
        _ann('a1', t0),
        _ann('a2', t0.add(const Duration(hours: 1))),
        _ann('a3', t0.add(const Duration(hours: 2))),
      ];
      expect(
        AnnouncementRead.countUnread(
          all,
          readMessageId: 'a1',
          myUserId: 'me',
        ),
        2,
      );
    });

    test('own announcement unread until explicitly read', () {
      final ann = _ann('a1', DateTime.utc(2026, 1, 1), sender: 'me');
      expect(
        AnnouncementRead.isUnread(
          announcement: ann,
          readMessageId: null,
          myUserId: 'me',
        ),
        isTrue,
      );
      expect(
        AnnouncementRead.isUnread(
          announcement: ann,
          readMessageId: 'a1',
          myUserId: 'me',
          allMessages: [ann],
        ),
        isFalse,
      );
    });
  });
}
