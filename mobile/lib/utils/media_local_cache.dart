import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'media_payload.dart';

/// 应用内私有媒体缓存（用户无感）：聊天内展示/播放用。
/// 导出到相册或 Download/IHope 由 [MediaSave] / [MediaDownloadIndex] 在用户主动操作时完成。
class MediaLocalCache {
  MediaLocalCache._();

  static Future<void> clearAll() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

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

  /// 磁盘已有媒体时，重建不含 b64 的轻量 plaintext。
  static Future<String?> localRefFromDisk(String messageId) async {
    final media = await load(messageId);
    if (media == null) return null;
    return jsonEncode({
      'media': media.kind,
      'local': true,
      'mime': media.mime,
      'name': media.name,
      if (media.durationMs != null) 'duration_ms': media.durationMs,
    });
  }

  /// 带正确扩展名的临时路径，供系统应用打开文件（仍在应用私有目录）。
  static Future<String?> openablePath(String messageId) async {
    final media = await load(messageId);
    if (media == null) return null;
    final base = await _dir();
    final msgDir = Directory('${base.path}/$messageId');
    if (!await msgDir.exists()) await msgDir.create(recursive: true);
    final safeName = media.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${msgDir.path}/$safeName';
    final file = File(path);
    if (!await file.exists() || await file.length() != media.bytes.length) {
      await file.writeAsBytes(media.bytes, flush: true);
    }
    return path;
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

  /// 从 plaintext 解析媒体：优先读应用内落盘；否则解析 inline b64（内存）。
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
    if (inline != null) return inline;
    if (await hasPayloadFile(messageId)) {
      return load(messageId);
    }
    return null;
  }
}
