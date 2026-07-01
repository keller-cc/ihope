import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// 保存结果：公共存储位置（content:// 或绝对路径）+ 用户可见说明。
class MediaSaveResult {
  const MediaSaveResult({
    required this.openPath,
    required this.displayLabel,
  });

  final String openPath;
  final String displayLabel;
}

/// 将媒体保存到系统公共目录（Pictures、Download、相册等）。
class MediaSave {
  static const _androidChannel = MethodChannel('com.ihope.ihope/media_save');

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  static bool isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic');
  }

  static String fileNameForSave(String name, {required bool isImage}) {
    return _safeName(name.isEmpty ? (isImage ? 'image.jpg' : 'file') : name);
  }

  static Future<MediaSaveResult> saveMedia({
    required List<int> bytes,
    required String name,
    void Function(double progress)? onProgress,
    bool forceGallery = false,
  }) async {
    final isImage = forceGallery || isImageName(name);
    final fileName = fileNameForSave(name, isImage: isImage);
    onProgress?.call(0);

    if (!kIsWeb && Platform.isAndroid) {
      return _saveAndroid(
        bytes: bytes,
        fileName: fileName,
        isImage: isImage,
        onProgress: onProgress,
      );
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/$fileName');
    await _writeBytes(tempFile, bytes, (p) => onProgress?.call(p * 0.85));
    try {
      if (!kIsWeb && Platform.isIOS) {
        return await _saveIos(
          tempFile: tempFile,
          fileName: fileName,
          isImage: isImage,
          onProgress: onProgress,
        );
      }
      return await _saveDesktop(
        tempFile: tempFile,
        fileName: fileName,
        onProgress: onProgress,
      );
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  static Future<bool> existsAt(String openPath) async {
    if (openPath.isEmpty) return false;
    if (openPath.startsWith('ios-gallery:')) return true;
    if (!kIsWeb && Platform.isAndroid && openPath.startsWith('content://')) {
      final ok = await _androidChannel.invokeMethod<bool>(
        'existsAt',
        {'path': openPath},
      );
      return ok ?? false;
    }
    return File(openPath).exists();
  }

  static String snackBarFor(MediaSaveResult result) {
    if (result.displayLabel.startsWith('Pictures/')) {
      return '已保存至 ${result.displayLabel}，请在文件管理 → 图片/Pictures 查看';
    }
    if (result.displayLabel.startsWith('Download/')) {
      return '已保存至 ${result.displayLabel}，请在文件管理 → 下载/Download 查看';
    }
    return '已保存至 ${result.displayLabel}';
  }

  static Future<Map<String, String>> _saveAndroidPublic({
    required List<int> bytes,
    required String fileName,
    required bool isImage,
  }) async {
    final result = await _androidChannel.invokeMethod<Map<Object?, Object?>>(
      'saveToPublic',
      {
        'bytes': bytes,
        'fileName': fileName,
        'isImage': isImage,
      },
    );
    if (result == null) throw StateError('保存失败：无返回结果');
    final openPath = result['openPath']?.toString();
    final displayLabel = result['displayLabel']?.toString();
    if (openPath == null || displayLabel == null) {
      throw StateError('保存失败：返回数据不完整');
    }
    return {'openPath': openPath, 'displayLabel': displayLabel};
  }

  static Future<void> _writeBytes(
    File file,
    List<int> bytes,
    void Function(double progress)? onProgress,
  ) async {
    if (bytes.isEmpty) {
      await file.writeAsBytes(bytes, flush: true);
      onProgress?.call(1);
      return;
    }
    const chunkSize = 64 * 1024;
    final raf = await file.open(mode: FileMode.write);
    try {
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = math.min(offset + chunkSize, bytes.length);
        await raf.writeFrom(bytes, offset, end);
        onProgress?.call(end / bytes.length);
      }
      await raf.flush();
    } finally {
      await raf.close();
    }
  }

  static Future<MediaSaveResult> _saveAndroid({
    required List<int> bytes,
    required String fileName,
    required bool isImage,
    void Function(double progress)? onProgress,
  }) async {
    final saved = await _saveAndroidPublic(
      bytes: bytes,
      fileName: fileName,
      isImage: isImage,
    );
    onProgress?.call(1);
    final openPath = saved['openPath'] as String?;
    final displayLabel = saved['displayLabel'] as String?;
    if (openPath == null || displayLabel == null) {
      throw StateError('保存失败：系统未返回文件路径');
    }
    if (!await existsAt(openPath)) {
      throw StateError('文件已写入但系统未索引，请稍后重试');
    }
    return MediaSaveResult(
      openPath: openPath,
      displayLabel: displayLabel,
    );
  }

  static Future<MediaSaveResult> _saveIos({
    required File tempFile,
    required String fileName,
    required bool isImage,
    void Function(double progress)? onProgress,
  }) async {
    if (isImage) {
      if (!await Gal.hasAccess(toAlbum: true)) {
        final ok = await Gal.requestAccess(toAlbum: true);
        if (!ok) throw StateError('需要相册权限才能保存图片');
      }
      await Gal.putImage(tempFile.path);
      onProgress?.call(1);
      return MediaSaveResult(
        openPath: 'ios-gallery:$fileName',
        displayLabel: '相册',
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final target = File('${dir.path}/$fileName');
    await tempFile.copy(target.path);
    onProgress?.call(1);
    return MediaSaveResult(
      openPath: target.path,
      displayLabel: displayPath(target.path),
    );
  }

  static Future<MediaSaveResult> _saveDesktop({
    required File tempFile,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final downloads =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final target = File('${downloads.path}/$fileName');
    await tempFile.copy(target.path);
    onProgress?.call(1);
    return MediaSaveResult(
      openPath: target.path,
      displayLabel: 'Download/$fileName',
    );
  }

  static String displayPath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    if (parts.length <= 2) return path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  static Future<OpenResult> openPath(String path) => OpenFile.open(path);
}
