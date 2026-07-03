import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kRecentEmojiMaxCount = 36;
const _kRecentEmojisKey = 'recent_emojis';

/// 将 [emoji] 插入最近列表：去重、最新在前、截断至 [maxCount]。
List<String> mergeRecentEmoji(
  List<String> current,
  String emoji, {
  int maxCount = kRecentEmojiMaxCount,
}) {
  if (emoji.isEmpty) return List<String>.from(current);
  final next = [emoji, ...current.where((e) => e != emoji)];
  if (next.length <= maxCount) return next;
  return next.sublist(0, maxCount);
}

/// 本地持久化最近使用的表情（设备级，非敏感数据）。
class RecentEmojiStore {
  RecentEmojiStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<List<String>> read() async {
    final raw = await _storage.read(key: _kRecentEmojisKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> record(String emoji) async {
    final current = await read();
    final next = mergeRecentEmoji(current, emoji);
    await _storage.write(key: _kRecentEmojisKey, value: jsonEncode(next));
    return next;
  }
}
