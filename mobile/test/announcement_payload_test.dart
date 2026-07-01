import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/utils/announcement_payload.dart';

void main() {
  group('AnnouncementPayload', () {
    test('encode and parse round trip', () {
      final p = AnnouncementPayload(title: '聚会', body: '周日 10 点 🙏');
      final raw = p.encode();
      final parsed = AnnouncementPayload.tryParse(raw);
      expect(parsed?.title, '聚会');
      expect(parsed?.body, '周日 10 点 🙏');
      expect(parsed?.displayTitle, '聚会');
    });

    test('plain text legacy body', () {
      final p = AnnouncementPayload.tryParse('旧版纯文本公告');
      expect(p?.title, '');
      expect(p?.body, '旧版纯文本公告');
      expect(p?.displayTitle, AnnouncementPayload.defaultTitle);
    });

    test('fromMessage uses plaintext', () {
      final msg = ChatMessage(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        type: 'announcement',
        ciphertext: 'x',
        createdAt: DateTime.utc(2026, 1, 1),
        plaintext: AnnouncementPayload(title: 'T', body: 'B').encode(),
      );
      final p = AnnouncementPayload.fromMessage(msg);
      expect(p.title, 'T');
      expect(p.body, 'B');
    });

    test('listPreview formats for conversation list', () {
      final p = AnnouncementPayload(title: '聚会', body: '周日十点集合');
      expect(p.listPreview, '[群公告] 聚会: 周日十点集合');
      expect(
        AnnouncementPayload.previewFromPlaintext(p.encode()),
        '[群公告] 聚会: 周日十点集合',
      );
    });

    test('previewFromPlaintext is idempotent', () {
      const formatted = '[群公告] 聚会: 周日十点集合';
      expect(AnnouncementPayload.previewFromPlaintext(formatted), formatted);
    });
  });
}
