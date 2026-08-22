import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 消息内 inline 图片预览（E2EE 附件缩略图）。
class ImageThumbnail {
  ImageThumbnail._();

  /// 气泡预览（约 720px JPEG）。
  static const previewMaxEdge = 720;

  /// 旧消息极小缩略图。
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
