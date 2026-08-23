import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/utils/media_local_cache.dart';

void main() {
  test('stripInlineMediaBytes removes preview and thumb base64', () {
    final raw = jsonEncode({
      'media': 'image',
      'local': true,
      'mime': 'image/jpeg',
      'name': 'a.jpg',
      'preview_b64': 'abc',
      'thumb_b64': 'def',
      'file_key_b64': 'key',
    });
    final slim = MediaLocalCache.stripInlineMediaBytes(raw);
    expect(slim, isNotNull);
    final map = jsonDecode(slim!) as Map<String, dynamic>;
    expect(map.containsKey('preview_b64'), isFalse);
    expect(map.containsKey('thumb_b64'), isFalse);
    expect(map['file_key_b64'], 'key');
    expect(map['local'], true);
  });
}
