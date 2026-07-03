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
    if (media != null) {
      await persistPayload(messageId, media);
      return jsonEncode({
        'media': media.kind,
        'local': true,
        'mime': media.mime,
        'name': media.name,
        if (media.durationMs != null) 'duration_ms': media.durationMs,
      });
    }
    final att = AttachmentPayload.tryParse(plaintext);
    if (att != null) {
      return jsonEncode({
        'media': att.kind,
        'local': true,
        'mime': att.mime,
        'name': att.name,
        'size': att.size,
        'file_key_b64': att.fileKeyB64,
        if (att.thumbBytes != null) 'thumb_b64': base64Encode(att.thumbBytes!),
        if (att.previewBytes != null)
          'preview_b64': base64Encode(att.previewBytes!),
      });
    }
    return null;
  }

  static int? expectedAttachmentBytes(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;
    final att = AttachmentPayload.tryParse(plaintext);
    if (att != null) return att.size;
    if (isLocalRef(plaintext)) {
      try {
        final map = jsonDecode(plaintext) as Map<String, dynamic>;
        if (map['file_key_b64'] is String) {
          final size = map['size'];
          if (size is int) return size;
          if (size is num) return size.round();
        }
      } catch (_) {}
    }
    return null;
  }

  static bool isRemoteImage(String? plaintext, String? fileId) {
    if (fileId != null && fileId.isNotEmpty) return true;
    final att = AttachmentPayload.tryParse(plaintext);
    if (att != null && att.kind == 'image') return true;
    if (isLocalRef(plaintext)) {
      try {
        final map = jsonDecode(plaintext!) as Map<String, dynamic>;
        return map['media'] == 'image' && map['file_key_b64'] is String;
      } catch (_) {}
    }
    return false;
  }

  /// 远程图片附件是否尚未拉取原图（仅有缩略图或本地文件体积不足）。
  static Future<bool> needsFullImageDownload({
    required String messageId,
    required String? plaintext,
    required String? fileId,
  }) async {
    if (!isRemoteImage(plaintext, fileId)) return false;
    if (!await hasPayloadFile(messageId)) return true;
    final expected = expectedAttachmentBytes(plaintext);
    if (expected == null || expected <= 0) return false;
    try {
      final len = await (await _bytesFile(messageId)).length();
      return len < expected * 0.9;
    } catch (_) {
      return true;
    }
  }

  /// 读取已落盘的原图；不含缩略图回退。
  static Future<MediaPayload?> loadFullImage(
    String messageId,
    String? plaintext,
    String? fileId,
  ) async {
    if (isRemoteImage(plaintext, fileId)) {
      if (!await hasPayloadFile(messageId)) return null;
      final local = await load(messageId);
      if (local == null) return null;
      final expected = expectedAttachmentBytes(plaintext);
      if (expected != null &&
          expected > 0 &&
          local.bytes.length < expected * 0.9) {
        return null;
      }
      return local;
    }
    final local = await load(messageId);
    if (local != null) return local;
    return MediaPayload.tryParse(plaintext);
  }

  /// 将 local 消息 ID 的缓存迁移到服务端 ID（乐观发送 → 发送成功）。
  static Future<void> migrateMessageId(String fromId, String toId) async {
    if (fromId == toId) return;
    final fromBytes = await _bytesFile(fromId);
    if (!await fromBytes.exists()) return;
    final toBytes = await _bytesFile(toId);
    await fromBytes.copy(toBytes.path);
    final fromMeta = await _metaFile(fromId);
    if (await fromMeta.exists()) {
      await fromMeta.copy((await _metaFile(toId)).path);
      await fromMeta.delete();
    }
    await fromBytes.delete();
  }

  /// 原图/文件已落盘后，生成保留 file_key 的 local 引用。
  static Future<String?> attachmentLocalRef(
    String messageId,
    String? existingPlaintext,
  ) async {
    if (!await hasPayloadFile(messageId)) return null;
    final media = await load(messageId);
    if (media == null) return null;
    final att = AttachmentPayload.fromPlaintext(existingPlaintext);
    return jsonEncode({
      'media': media.kind,
      'local': true,
      'mime': media.mime,
      'name': media.name,
      if (att != null) ...{
        'size': att.size,
        'file_key_b64': att.fileKeyB64,
        if (att.thumbBytes != null)
          'thumb_b64': base64Encode(att.thumbBytes!),
        if (att.previewBytes != null)
          'preview_b64': base64Encode(att.previewBytes!),
      },
    });
  }

  static Future<void> persistPayload(
    String messageId,
    MediaPayload media, {
    int? originalSize,
  }) async {
    await (await _bytesFile(messageId)).writeAsBytes(media.bytes, flush: true);
    await (await _metaFile(messageId)).writeAsString(
      jsonEncode({
        'media': media.kind,
        'mime': media.mime,
        'name': media.name,
        if (media.durationMs != null) 'duration_ms': media.durationMs,
        if (originalSize != null) 'size': originalSize,
        if (originalSize != null) 'full': true,
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
        durationMs: readDurationMs(map['duration_ms']),
      );
    } catch (_) {
      return null;
    }
  }

  static int? durationMsFromPlaintext(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      return readDurationMs(map['duration_ms']);
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

  /// 聊天列表/气泡用预览图：优先消息内 preview，不拉取服务端原图。
  static Future<MediaPayload?> resolvePreview(
    String messageId,
    String? plaintext,
  ) async {
    if (plaintext == null || plaintext.isEmpty) return null;

    if (await hasPayloadFile(messageId)) {
      final local = await load(messageId);
      if (local != null && local.kind == 'image') return local;
    }

    final fromInline = _imageFromPlaintextMap(plaintext);
    if (fromInline != null) return fromInline;

    final att = AttachmentPayload.fromPlaintext(plaintext);
    if (att != null && att.kind == 'image') {
      if (att.previewBytes != null && att.previewBytes!.isNotEmpty) {
        return MediaPayload(
          kind: 'image',
          mime: att.mime,
          name: att.name,
          bytes: att.previewBytes!,
        );
      }
      if (att.thumbBytes != null && att.thumbBytes!.isNotEmpty) {
        return MediaPayload(
          kind: 'image',
          mime: att.mime,
          name: att.name,
          bytes: att.thumbBytes!,
        );
      }
    }
    return null;
  }

  static MediaPayload? _imageFromPlaintextMap(String plaintext) {
    final inline = MediaPayload.tryParse(plaintext);
    if (inline != null && inline.kind == 'image') return inline;
    if (!isLocalRef(plaintext)) return null;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      if (map['media'] != 'image') return null;
      if (map['preview_b64'] is String) {
        return MediaPayload(
          kind: 'image',
          mime: map['mime'] as String? ?? 'image/jpeg',
          name: map['name'] as String? ?? 'image.jpg',
          bytes: base64Decode(map['preview_b64'] as String),
        );
      }
      if (map['thumb_b64'] is String) {
        return MediaPayload(
          kind: 'image',
          mime: map['mime'] as String? ?? 'image/jpeg',
          name: map['name'] as String? ?? 'image.jpg',
          bytes: base64Decode(map['thumb_b64'] as String),
        );
      }
    } catch (_) {}
    return null;
  }

  /// 从 plaintext 解析媒体：优先读应用内落盘；否则解析 inline b64（内存）。
  static Future<MediaPayload?> resolve(
    String messageId,
    String? plaintext,
  ) async {
    if (plaintext == null || plaintext.isEmpty) {
      return load(messageId);
    }
    if (isLocalRef(plaintext)) {
      final local = await load(messageId);
      if (local != null) return local;
      final preview = _imageFromPlaintextMap(plaintext);
      if (preview != null) return preview;
    }
    final inline = MediaPayload.tryParse(plaintext);
    if (inline != null) return inline;
    final att = AttachmentPayload.tryParse(plaintext);
    if (att != null) {
      final local = await load(messageId);
      if (local != null) return local;
      if (att.kind == 'image') {
        if (att.previewBytes != null && att.previewBytes!.isNotEmpty) {
          return MediaPayload(
            kind: 'image',
            mime: att.mime,
            name: att.name,
            bytes: att.previewBytes!,
          );
        }
        if (att.thumbBytes != null && att.thumbBytes!.isNotEmpty) {
          return MediaPayload(
            kind: 'image',
            mime: att.mime,
            name: att.name,
            bytes: att.thumbBytes!,
          );
        }
      }
      return null;
    }
    if (await hasPayloadFile(messageId)) {
      return load(messageId);
    }
    return null;
  }

  static bool isAttachmentRef(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return false;
    if (AttachmentPayload.tryParse(plaintext) != null) return true;
    if (!isLocalRef(plaintext)) return false;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      return map['file_key_b64'] is String;
    } catch (_) {
      return false;
    }
  }
}
