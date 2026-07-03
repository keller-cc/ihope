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

    test('reading one announcement does not mark others read', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final all = [
        _ann('a1', t0),
        _ann('a2', t0.add(const Duration(hours: 1))),
        _ann('a3', t0.add(const Duration(hours: 2))),
      ];
      const readIds = {'a3'};

      expect(
        AnnouncementRead.isUnread(
          announcement: all[0],
          readIds: readIds,
          myUserId: 'me',
        ),
        isTrue,
      );
      expect(
        AnnouncementRead.isUnread(
          announcement: all[1],
          readIds: readIds,
          myUserId: 'me',
        ),
        isTrue,
      );
      expect(
        AnnouncementRead.isUnread(
          announcement: all[2],
          readIds: readIds,
          myUserId: 'me',
        ),
        isFalse,
      );
      expect(
        AnnouncementRead.countUnread(all, readIds: readIds, myUserId: 'me'),
        2,
      );
    });

    test('countUnread with multiple read ids', () {
      final t0 = DateTime.utc(2026, 1, 1);
      final all = [
        _ann('a1', t0),
        _ann('a2', t0.add(const Duration(hours: 1))),
        _ann('a3', t0.add(const Duration(hours: 2))),
      ];
      expect(
        AnnouncementRead.countUnread(
          all,
          readIds: {'a1', 'a3'},
          myUserId: 'me',
        ),
        1,
      );
    });

    test('own announcement unread until explicitly read', () {
      final ann = _ann('a1', DateTime.utc(2026, 1, 1), sender: 'me');
      expect(
        AnnouncementRead.isUnread(
          announcement: ann,
          readIds: {},
          myUserId: 'me',
        ),
        isTrue,
      );
      expect(
        AnnouncementRead.isUnread(
          announcement: ann,
          readIds: {'a1'},
          myUserId: 'me',
          allMessages: [ann],
        ),
        isFalse,
      );
    });
  });
}
