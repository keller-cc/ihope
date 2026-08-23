import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 消息内 inline 图片预览（E2EE 附件缩略图）。
class ImageThumbnail {
  ImageThumbnail._();

  /// 旧消息极小缩略图（仅 thumb_b64）。
  static const thumbMaxEdge = 200;

  /// 气泡预览边长；原图仍走附件上传，避免把整图塞进 E2EE 明文。
  static const previewMaxEdge = 480;
  static const previewQuality = 72;

  static Future<Uint8List> generatePreview(List<int> imageBytes) async {
    return _resize(imageBytes, previewMaxEdge, quality: previewQuality);
  }

  /// 解码图片像素尺寸（用于预览与原图对齐）。
  static ({int width, int height})? pixelSize(List<int> imageBytes) {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) return null;
    return (width: decoded.width, height: decoded.height);
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
