import 'dart:convert';

import '../models/message.dart';

/// 群公告正文：`ann:v1:` + JSON `{title, body}`；兼容旧版纯文本。
class AnnouncementPayload {
  const AnnouncementPayload({
    required this.title,
    required this.body,
  });

  static const prefix = 'ann:v1:';
  static const defaultTitle = '群公告';

  final String title;
  final String body;

  String get displayTitle {
    final t = title.trim();
    return t.isEmpty ? defaultTitle : t;
  }

  /// 会话列表等场景的摘要文案。
  String get listPreview {
    final bodyText = body.trim();
    if (bodyText.isEmpty) return '[群公告] $displayTitle';
    final short = bodyText.length > 36
        ? '${bodyText.substring(0, 36)}…'
        : bodyText;
    final hasCustomTitle = title.trim().isNotEmpty;
    if (hasCustomTitle) return '[群公告] $displayTitle: $short';
    return '[群公告] $short';
  }

  static String previewFromPlaintext(String? plaintext) {
    if (plaintext == null || plaintext.trim().isEmpty) return '[群公告]';
    final raw = plaintext.trim();
    if (raw.startsWith('[群公告]')) return raw;
    return tryParse(raw)?.listPreview ?? '[群公告]';
  }

  String encode() => '$prefix${jsonEncode({
        'title': title.trim(),
        'body': body.trim(),
      })}';

  static AnnouncementPayload? tryParse(String? plaintext) {
    if (plaintext == null) return null;
    final raw = plaintext.trim();
    if (raw.isEmpty) return null;
    if (!raw.startsWith(prefix)) {
      return AnnouncementPayload(title: '', body: raw);
    }
    try {
      final json = jsonDecode(raw.substring(prefix.length));
      if (json is! Map<String, dynamic>) return null;
      return AnnouncementPayload(
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
      );
    } catch (_) {
      return AnnouncementPayload(title: '', body: raw);
    }
  }

  static AnnouncementPayload fromMessage(ChatMessage msg) {
    return tryParse(msg.plaintext) ??
        AnnouncementPayload(title: '', body: msg.displayText);
  }
}
