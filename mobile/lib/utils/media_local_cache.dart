import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'media_payload.dart';

/// 语音/图片/文件二进制落盘，消息缓存只存元数据，避免反复向服务端拉取。
class MediaLocalCache {
  MediaLocalCache._();

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/ihope_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _bytesFile(String messageId) async {
    final dir = await _dir();
    return File('${dir.path}/$messageId.bin');
  }

  static Future<File> _metaFile(String messageId) async {
    final dir = await _dir();
    return File('${dir.path}/$messageId.json');
  }

  static String? localKind(String? plaintext) {
    if (!isLocalRef(plaintext)) return null;
    try {
      final map = jsonDecode(plaintext!) as Map<String, dynamic>;
      return map['media'] as String?;
    } catch (_) {
      return null;
    }
  }

  static bool isLocalRef(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return false;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      return map['local'] == true && map['media'] is String;
    } catch (_) {
      return false;
    }
  }

  /// 将完整 media plaintext 写入磁盘，并返回不含 b64 的轻量 plaintext。
  static Future<String?> persistPlaintext(
    String messageId,
    String plaintext,
  ) async {
    final media = MediaPayload.tryParse(plaintext);
    if (media == null) return null;
    await persistPayload(messageId, media);
    return jsonEncode({
      'media': media.kind,
      'local': true,
      'mime': media.mime,
      'name': media.name,
      if (media.durationMs != null) 'duration_ms': media.durationMs,
    });
  }

  static Future<void> persistPayload(
    String messageId,
    MediaPayload media,
  ) async {
    await (await _bytesFile(messageId)).writeAsBytes(media.bytes, flush: true);
    await (await _metaFile(messageId)).writeAsString(
      jsonEncode({
        'media': media.kind,
        'mime': media.mime,
        'name': media.name,
        if (media.durationMs != null) 'duration_ms': media.durationMs,
      }),
      flush: true,
    );
  }

  static Future<MediaPayload?> load(String messageId) async {
    final bytesFile = await _bytesFile(messageId);
    final metaFile = await _metaFile(messageId);
    if (!await bytesFile.exists() || !await metaFile.exists()) return null;
    try {
      final map = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      return MediaPayload(
        kind: map['media'] as String,
        mime: map['mime'] as String? ?? 'application/octet-stream',
        name: map['name'] as String? ?? 'file',
        bytes: await bytesFile.readAsBytes(),
        durationMs: map['duration_ms'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  static int? durationMsFromPlaintext(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      return map['duration_ms'] as int?;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasPayloadFile(String messageId) async {
    return (await _bytesFile(messageId)).exists();
  }

  /// 本地 plaintext 是否真能读出媒体（inline b64 或已落盘文件）。
  static Future<bool> isPlaintextAvailable(
    String messageId,
    String? plaintext,
  ) async {
    if (plaintext == null || plaintext.isEmpty) return false;
    if (isLocalRef(plaintext)) {
      return hasPayloadFile(messageId);
    }
    return MediaPayload.tryParse(plaintext) != null;
  }

  /// 从 plaintext（含 b64 或 local 引用）解析媒体，优先读本地文件。
  static Future<MediaPayload?> resolve(
    String messageId,
    String? plaintext,
  ) async {
    if (plaintext == null || plaintext.isEmpty) return null;
    if (isLocalRef(plaintext)) {
      final local = await load(messageId);
      if (local != null) return local;
    }
    final inline = MediaPayload.tryParse(plaintext);
    if (inline != null) {
      await persistPayload(messageId, inline);
    }
    return inline;
  }
}
