import 'dart:convert';

/// IM 附件大小格式化（实际上限见 [AppConfig.maxFileBytes]）。
String formatFileSizeMb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// 从 JSON 字段解析毫秒时长（兼容 int / double）。
int? readDurationMs(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
}

/// 语音时长展示：与录音蒙版一致，按整秒向上取整。
int voiceDurationSecondsFromMs(int? ms) {
  final raw = ms ?? 0;
  if (raw <= 0) return 1;
  return (raw + 999) ~/ 1000;
}

/// 将原始录音毫秒归一化为整秒（用于写入消息 metadata）。
int normalizeVoiceDurationMs(int ms) =>
    voiceDurationSecondsFromMs(ms) * 1000;

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
      if (map['local'] == true) return null;
      if (map['file_key_b64'] is String) return null;
      if (map['media'] is! String || map['b64'] is! String) return null;
      return MediaPayload(
        kind: map['media'] as String,
        mime: map['mime'] as String? ?? 'application/octet-stream',
        name: map['name'] as String? ?? 'file',
        bytes: base64Decode(map['b64'] as String),
        durationMs: readDurationMs(map['duration_ms']),
      );
    } catch (_) {
      return null;
    }
  }

  static String previewFromPlaintext(String? plaintext, String type) {
    if (plaintext == null || plaintext.isEmpty) {
      return previewLabel(null, type);
    }
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      if (map['local'] == true && map['media'] is String) {
        switch (map['media'] as String) {
          case 'image':
            return '[图片]';
          case 'audio':
            final sec = voiceDurationSecondsFromMs(
              readDurationMs(map['duration_ms']),
            );
            return sec > 0 ? '[语音 ${sec}秒]' : '[语音]';
          case 'file':
            return '[文件] ${map['name'] ?? 'file'}';
          default:
            return '[${map['media']}]';
        }
      }
      if (map['file_key_b64'] is String && map['media'] is String) {
        switch (map['media'] as String) {
          case 'image':
            return '[图片]';
          case 'file':
            return '[文件] ${map['name'] ?? 'file'}';
        }
      }
    } catch (_) {}
    return previewLabel(plaintext, type);
  }

  static String previewLabel(String? plaintext, String type) {
    final media = tryParse(plaintext);
    if (media != null) {
      switch (media.kind) {
        case 'image':
          return '[图片]';
        case 'audio':
          final sec = voiceDurationSecondsFromMs(media.durationMs);
          return sec > 0 ? '[语音 ${sec}秒]' : '[语音]';
        case 'file':
          return '[文件] ${media.name}';
        default:
          return '[${media.kind}]';
      }
    }
    final att = AttachmentPayload.tryParse(plaintext);
    if (att != null) {
      switch (att.kind) {
        case 'image':
          return '[图片]';
        case 'file':
          return '[文件] ${att.name}';
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

/// 图片/文件远程附件：元数据 + file_key 在消息内，blob 在服务端。
class AttachmentPayload {
  AttachmentPayload({
    required this.kind,
    required this.mime,
    required this.name,
    required this.size,
    required this.fileKeyB64,
    this.previewBytes,
    this.thumbBytes,
  });

  final String kind;
  final String mime;
  final String name;
  final int size;
  final String fileKeyB64;
  final List<int>? previewBytes;
  final List<int>? thumbBytes;

  String encodePlaintext() => jsonEncode({
        'media': kind,
        'mime': mime,
        'name': name,
        'size': size,
        'file_key_b64': fileKeyB64,
        if (previewBytes != null) 'preview_b64': base64Encode(previewBytes!),
        if (thumbBytes != null) 'thumb_b64': base64Encode(thumbBytes!),
      });

  static AttachmentPayload? tryParse(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      if (map['local'] == true) return null;
      return _fromMap(map);
    } catch (_) {
      return null;
    }
  }

  /// 解析附件元数据（含 local 引用，用于下载原图/文件）。
  static AttachmentPayload? fromPlaintext(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      return _fromMap(map, allowLocal: true);
    } catch (_) {
      return null;
    }
  }

  static AttachmentPayload? _fromMap(
    Map<String, dynamic> map, {
    bool allowLocal = false,
  }) {
    if (!allowLocal && map['local'] == true) return null;
    if (map['media'] is! String) return null;
    final kind = map['media'] as String;
    if (kind != 'image' && kind != 'file') return null;
    if (map['file_key_b64'] is! String) return null;
    if (map['b64'] is String) return null;
    final sizeRaw = map['size'];
    final size = sizeRaw is int
        ? sizeRaw
        : sizeRaw is num
            ? sizeRaw.round()
            : 0;
    return AttachmentPayload(
      kind: kind,
      mime: map['mime'] as String? ?? 'application/octet-stream',
      name: map['name'] as String? ?? 'file',
      size: size,
      fileKeyB64: map['file_key_b64'] as String,
      previewBytes: map['preview_b64'] is String
          ? base64Decode(map['preview_b64'] as String)
          : null,
      thumbBytes: map['thumb_b64'] is String
          ? base64Decode(map['thumb_b64'] as String)
          : null,
    );
  }
}
