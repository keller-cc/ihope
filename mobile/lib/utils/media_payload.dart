import 'dart:convert';

const kMaxMediaBytes = 8 * 1024 * 1024;
const kMaxAudioBytes = 512 * 1024;
const kMaxVoiceDuration = Duration(seconds: 60);

class MediaPayload {
  MediaPayload({
    required this.kind,
    required this.mime,
    required this.name,
    required this.bytes,
    this.durationMs,
  });

  final String kind;
  final String mime;
  final String name;
  final List<int> bytes;
  final int? durationMs;

  String encodePlaintext() => jsonEncode({
        'media': kind,
        'mime': mime,
        'name': name,
        'b64': base64Encode(bytes),
        if (durationMs != null) 'duration_ms': durationMs,
      });

  static MediaPayload? tryParse(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      if (map['media'] is! String || map['b64'] is! String) return null;
      return MediaPayload(
        kind: map['media'] as String,
        mime: map['mime'] as String? ?? 'application/octet-stream',
        name: map['name'] as String? ?? 'file',
        bytes: base64Decode(map['b64'] as String),
        durationMs: map['duration_ms'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  static String previewLabel(String? plaintext, String type) {
    final media = tryParse(plaintext);
    if (media != null) {
      switch (media.kind) {
        case 'image':
          return '[图片]';
        case 'audio':
          final sec = ((media.durationMs ?? 0) / 1000).round();
          return sec > 0 ? '[语音 ${sec}秒]' : '[语音]';
        case 'file':
          return '[文件] ${media.name}';
        default:
          return '[${media.kind}]';
      }
    }
    switch (type) {
      case 'image':
        return '[图片]';
      case 'audio':
        return '[语音]';
      case 'file':
        return '[文件]';
      default:
        return plaintext ?? '';
    }
  }
}
