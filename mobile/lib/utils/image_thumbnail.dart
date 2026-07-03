import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 聊天图片内联预览与缩略图（内联于 E2EE 消息）。
class ImageThumbnail {
  ImageThumbnail._();

  /// 列表气泡用预览图（较清晰，非极小缩略图）。
  static const previewMaxEdge = 720;

  /// 兼容旧消息的极小缩略图。
  static const thumbMaxEdge = 200;

  static Future<Uint8List> generatePreview(List<int> imageBytes) async {
    return _resize(imageBytes, previewMaxEdge, quality: 82);
  }

  static Future<Uint8List> generate(List<int> imageBytes) async {
    return _resize(imageBytes, thumbMaxEdge, quality: 70);
  }

  static Future<Uint8List> _resize(
    List<int> imageBytes,
    int maxEdge, {
    required int quality,
  }) async {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw StateError('无法解析图片');
    }
    final resized = img.copyResize(
      decoded,
      width: maxEdge,
      height: maxEdge,
      maintainAspect: true,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }
}
