import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'media_save.dart';

/// 记录已下载媒体（按消息 id），重进会话可恢复「已保存」状态。
class MediaDownloadRecord {
  const MediaDownloadRecord({
    required this.messageId,
    required this.openPath,
    required this.displayLabel,
  });

  final String messageId;
  final String openPath;
  final String displayLabel;

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'openPath': openPath,
        'displayLabel': displayLabel,
      };

  factory MediaDownloadRecord.fromJson(Map<String, dynamic> json) {
    return MediaDownloadRecord(
      messageId: json['messageId'] as String,
      openPath: (json['openPath'] ?? json['localPath']) as String,
      displayLabel: json['displayLabel'] as String? ?? '',
    );
  }
}

class MediaDownloadIndex {
  static Map<String, MediaDownloadRecord>? _cache;

  static Future<File> _indexFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ihope_media_downloads.json');
  }

  static Future<Map<String, MediaDownloadRecord>> _loadAll() async {
    if (_cache != null) return _cache!;
    final file = await _indexFile();
    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) {
        _cache = {};
        return _cache!;
      }
      _cache = raw.map((key, value) {
        return MapEntry(
          key.toString(),
          MediaDownloadRecord.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        );
      });
      return _cache!;
    } catch (_) {
      _cache = {};
      return _cache!;
    }
  }

  static Future<void> _persist() async {
    final map = _cache ?? {};
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  static Future<void> put(MediaDownloadRecord record) async {
    final map = await _loadAll();
    map[record.messageId] = record;
    await _persist();
  }

  static Future<MediaDownloadRecord?> lookup(String messageId) async {
    final map = await _loadAll();
    final record = map[messageId];
    if (record == null) return null;
    if (!await MediaSave.existsAt(record.openPath)) {
      map.remove(messageId);
      await _persist();
      return null;
    }
    return record;
  }

  /// 保存到公共目录并写入索引。
  static Future<MediaSaveResult> saveForMessage({
    required String messageId,
    required List<int> bytes,
    required String name,
    bool forceGallery = false,
    void Function(double progress)? onProgress,
  }) async {
    final result = await MediaSave.saveMedia(
      bytes: bytes,
      name: name,
      forceGallery: forceGallery,
      onProgress: onProgress,
    );
    await put(
      MediaDownloadRecord(
        messageId: messageId,
        openPath: result.openPath,
        displayLabel: result.displayLabel,
      ),
    );
    return result;
  }
}
