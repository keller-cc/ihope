import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 聊天图片缩略图（内联于 E2EE 消息）。
class ImageThumbnail {
  ImageThumbnail._();

  static const maxEdge = 200;

  static Future<Uint8List> generate(List<int> imageBytes) async {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw StateError('无法解析图片');
    }
    final thumb = img.copyResize(
      decoded,
      width: maxEdge,
      height: maxEdge,
      maintainAspect: true,
    );
    return Uint8List.fromList(img.encodeJpg(thumb, quality: 70));
  }
}
