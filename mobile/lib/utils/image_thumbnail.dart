import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 消息内 inline 图片预览（E2EE 附件缩略图）。
class ImageThumbnail {
  ImageThumbnail._();

  /// 旧消息极小缩略图（仅 thumb_b64）。
  static const thumbMaxEdge = 200;

  /// 气泡/查看器预览：与原图相同像素尺寸，仅 JPEG 压缩降体积。
  static const previewQuality = 82;

  static Future<Uint8List> generatePreview(List<int> imageBytes) async {
    return _compressSameDimensions(imageBytes, quality: previewQuality);
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

  static Future<Uint8List> _compressSameDimensions(
    List<int> imageBytes, {
    required int quality,
  }) async {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw StateError('无法解析图片');
    }
    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
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
