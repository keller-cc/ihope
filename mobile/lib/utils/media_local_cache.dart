import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'media_payload.dart';
import 'image_thumbnail.dart';
import 'media_retry_callback.dart';

/// 聊天媒体私有缓存；导出相册见 [MediaSave] / [MediaDownloadIndex]。
class MediaLocalCache {
  MediaLocalCache._();

  static const _fullImageRatio = 0.9;

  static final Map<String, MediaPayload> _imagePreviewMem = {};

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
      if (media.kind == 'image') {
        try {
          final preview = await ImageThumbnail.generatePreview(media.bytes);
          final size = ImageThumbnail.pixelSize(preview);
          _rememberImagePreview(
            messageId,
            media.mime,
            media.name,
            preview,
          );
          return jsonEncode({
            'media': media.kind,
            'local': true,
            'mime': media.mime,
            'name': media.name,
            'preview_b64': base64Encode(preview),
            if (size != null) 'image_width': size.width,
            if (size != null) 'image_height': size.height,
          });
        } catch (_) {}
      }
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

  static bool hasFullImageBytes(int byteLen, String? plaintext) {
    final expected = expectedAttachmentBytes(plaintext);
    if (expected != null && expected > 0) {
      return byteLen >= expected * _fullImageRatio;
    }
    if (expected == 0) return false;
    final att = AttachmentPayload.tryParse(plaintext);
    if (att != null && att.kind == 'image') {
      final preview = att.previewBytes ?? att.thumbBytes;
      if (preview != null && preview.isNotEmpty) {
        return byteLen > preview.length * 1.2;
      }
    }
    return true;
  }

  static Future<bool> needsFullImageDownload({
    required String messageId,
    required String? plaintext,
    required String? fileId,
  }) async {
    if (!isRemoteImage(plaintext, fileId)) return false;
    if (!await hasPayloadFile(messageId)) return true;
    final expected = expectedAttachmentBytes(plaintext);
    try {
      final len = await (await _bytesFile(messageId)).length();
      if (expected != null && expected > 0) {
        return len < expected * _fullImageRatio;
      }
      return !hasFullImageBytes(len, plaintext);
    } catch (_) {
      return true;
    }
  }

  /// 仅读本地已落盘原图；不触发网络。
  static Future<Uint8List?> tryLoadFullImageBytes({
    required String messageId,
    required String? plaintext,
    required String? fileId,
  }) async {
    final full = await loadFullImage(messageId, plaintext, fileId);
    if (full == null || full.bytes.isEmpty) return null;
    return Uint8List.fromList(full.bytes);
  }

  /// 优先本地原图；缺失且需要下载时调用 [downloadIfNeeded]，再读本地。
  static Future<Uint8List> resolveFullImageBytes({
    required String messageId,
    required String? plaintext,
    required String? fileId,
    MediaDownloadCallback? downloadIfNeeded,
  }) async {
    final cached = await tryLoadFullImageBytes(
      messageId: messageId,
      plaintext: plaintext,
      fileId: fileId,
    );
    if (cached != null) return cached;

    if (await needsFullImageDownload(
      messageId: messageId,
      plaintext: plaintext,
      fileId: fileId,
    )) {
      if (downloadIfNeeded == null) {
        throw StateError('无法下载原图');
      }
      await downloadIfNeeded();
    }

    final after = await tryLoadFullImageBytes(
      messageId: messageId,
      plaintext: plaintext,
      fileId: fileId,
    );
    if (after != null) return after;
    throw StateError('原图不可用');
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
      if (!hasFullImageBytes(local.bytes.length, plaintext)) return null;
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
    _migratePreviewMemory(fromId, toId);
  }

  static void _migratePreviewMemory(String fromId, String toId) {
    if (fromId == toId) return;
    final preview = _imagePreviewMem.remove(fromId);
    if (preview != null) {
      _imagePreviewMem[toId] = preview;
    }
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
    List<int>? previewBytes = att?.previewBytes ?? att?.thumbBytes;
    if (media.kind == 'image' &&
        (previewBytes == null || previewBytes.isEmpty)) {
      previewBytes = await _previewBytesForImage(messageId, media.bytes);
    }
    return jsonEncode({
      'media': media.kind,
      'local': true,
      'mime': media.mime,
      'name': media.name,
      if (att != null) ...{
        'size': att.size,
        'file_key_b64': att.fileKeyB64,
      },
      if (previewBytes != null && previewBytes.isNotEmpty)
        'preview_b64': base64Encode(previewBytes),
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
        'duration_ms': ?media.durationMs,
        'size': ?originalSize,
        if (originalSize != null) 'full': true,
      }),
      flush: true,
    );
    if (media.kind == 'image') {
      try {
        final preview = await ImageThumbnail.generatePreview(media.bytes);
        _rememberImagePreview(messageId, media.mime, media.name, preview);
      } catch (_) {}
    }
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
    if (media.kind == 'image') {
      final preview = await _previewBytesForImage(messageId, media.bytes);
      return jsonEncode({
        'media': media.kind,
        'local': true,
        'mime': media.mime,
        'name': media.name,
        if (preview != null) 'preview_b64': base64Encode(preview),
      });
    }
    return jsonEncode({
      'media': media.kind,
      'local': true,
      'mime': media.mime,
      'name': media.name,
      if (media.durationMs != null) 'duration_ms': media.durationMs,
    });
  }

  /// 本地引用缺 preview 时，从磁盘原图生成并写回 plaintext。
  static Future<String?> enrichLocalRefWithPreview(
    String messageId,
    String? plaintext,
  ) async {
    if (plaintext == null || plaintext.isEmpty) return null;
    if (!isLocalRef(plaintext)) return plaintext;
    if (hasInlineImagePreview(plaintext)) return plaintext;
    try {
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      if (map['media'] != 'image') return plaintext;
      final media = await load(messageId);
      if (media == null || media.kind != 'image') return plaintext;
      final preview = await _previewBytesForImage(messageId, media.bytes);
      if (preview == null) return plaintext;
      map['preview_b64'] = base64Encode(preview);
      return jsonEncode(map);
    } catch (_) {
      return plaintext;
    }
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

  /// 去掉 plaintext 里的 base64 媒体字节，避免 SQLite 单行撑爆 CursorWindow。
  static String? stripInlineMediaBytes(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return plaintext;
    try {
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map) return plaintext;
      final map = Map<String, dynamic>.from(decoded);
      var changed = false;
      for (final key in const ['preview_b64', 'thumb_b64', 'b64']) {
        if (map.remove(key) != null) changed = true;
      }
      return changed ? jsonEncode(map) : plaintext;
    } catch (_) {
      return plaintext;
    }
  }

  /// 消息 plaintext 是否含可展示的 inline 图片预览（无需原图落盘）。
  static bool hasInlineImagePreview(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return false;
    return _imageFromPlaintextMap(plaintext) != null;
  }

  /// 本地 plaintext 是否真能读出媒体（inline b64 或已落盘文件）。
  static Future<bool> isPlaintextAvailable(
    String messageId,
    String? plaintext,
  ) async {
    if (plaintext == null || plaintext.isEmpty) return false;
    if (hasInlineImagePreview(plaintext)) return true;
    if (isLocalRef(plaintext)) {
      return hasPayloadFile(messageId);
    }
    return MediaPayload.tryParse(plaintext) != null;
  }

  static MediaPayload? resolvePreviewSync(
    String? plaintext, {
    String? messageId,
  }) {
    if (messageId != null) {
      final mem = _imagePreviewMem[messageId];
      if (mem != null) return mem;
    }
    if (plaintext == null || plaintext.isEmpty) return null;
    final fromInline = _imageFromPlaintextMap(plaintext);
    if (fromInline != null) return fromInline;
    final att = AttachmentPayload.fromPlaintext(plaintext);
    return att != null ? _imagePreviewFromAttachment(att) : null;
  }

  static Future<MediaPayload?> resolvePreview(
    String messageId,
    String? plaintext, {
    String? fileId,
  }) async {
    if (plaintext == null || plaintext.isEmpty) return null;

    final sync = resolvePreviewSync(plaintext, messageId: messageId);
    if (sync != null) return sync;

    if (await hasPayloadFile(messageId)) {
      final local = await load(messageId);
      if (local != null && local.kind == 'image') {
        final preview = await _previewBytesForImage(messageId, local.bytes);
        if (preview != null) {
          return MediaPayload(
            kind: 'image',
            mime: local.mime,
            name: local.name,
            bytes: preview,
          );
        }
      }
    }

    return null;
  }

  static MediaPayload? _imagePreviewFromAttachment(AttachmentPayload att) {
    if (att.kind != 'image') return null;
    final bytes = att.previewBytes ?? att.thumbBytes;
    if (bytes == null || bytes.isEmpty) return null;
    return MediaPayload(
      kind: 'image',
      mime: att.mime,
      name: att.name,
      bytes: bytes,
    );
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

  /// 仅将 inline 图片压缩为 preview 写入 plaintext，不落盘原图。
  static Future<String?> compactImagePreviewOnly(String plaintext) async {
    final media = MediaPayload.tryParse(plaintext);
    if (media == null || media.kind != 'image') return null;
    try {
      final preview = await ImageThumbnail.generatePreview(media.bytes);
      return jsonEncode({
        'media': 'image',
        'local': true,
        'mime': media.mime,
        'name': media.name,
        'preview_b64': base64Encode(preview),
      });
    } catch (_) {
      return null;
    }
  }
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
      return _imagePreviewFromAttachment(att);
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

  static void _rememberImagePreview(
    String messageId,
    String mime,
    String name,
    List<int> previewBytes,
  ) {
    if (previewBytes.isEmpty) return;
    _imagePreviewMem[messageId] = MediaPayload(
      kind: 'image',
      mime: mime,
      name: name,
      bytes: previewBytes,
    );
  }

  static Future<List<int>?> _previewBytesForImage(
    String messageId,
    List<int> imageBytes,
  ) async {
    final mem = _imagePreviewMem[messageId];
    if (mem != null && mem.bytes.isNotEmpty) return mem.bytes;
    try {
      final preview = await ImageThumbnail.generatePreview(imageBytes);
      _rememberImagePreview(
        messageId,
        'image/jpeg',
        'image.jpg',
        preview,
      );
      return preview;
    } catch (_) {
      return null;
    }
  }
}
