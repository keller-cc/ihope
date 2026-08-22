import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../utils/media_local_cache.dart';
import '../../utils/media_payload.dart';
import '../../utils/media_retry_callback.dart';
import '../../utils/media_save.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/image_viewer_screen.dart';

/// 聊天图片查看：立即打开预览，原图在查看器内静默补全；支持左右滑动浏览会话内图片。
class ChatImageLauncher {
  ChatImageLauncher._();

  static Future<void> open(
    BuildContext context,
    ChatMessage msg, {
    MediaPayload? fallbackPreview,
    List<ChatMessage>? imageGallery,
    MediaRetryCallback? onMediaRetry,
  }) async {
    var gallery = imageGallery != null && imageGallery.isNotEmpty
        ? galleryFromMessages(imageGallery)
        : <ChatMessage>[msg];
    var index = gallery.indexWhere((m) => m.id == msg.id);
    if (index < 0) {
      gallery = [msg, ...gallery];
      index = 0;
    }

    final pages = gallery
        .map(
          (m) => pageDataFor(
            m,
            onMediaRetry: onMediaRetry,
            fallbackPreview: m.id == msg.id ? fallbackPreview : null,
          ),
        )
        .toList();

    final previewBytes = pages[index].bytes;
    if (previewBytes != null && context.mounted) {
      await precacheImage(MemoryImage(previewBytes), context);
    }

    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      appPageRoute(
        wrapNavigationPopScope: false,
        builder: (_) => ImageViewerScreen(
          pages: pages,
          initialIndex: index,
        ),
      ),
    );
  }

  /// 会话内图片消息，按时间从早到晚排序（左滑看较新的图）。
  static List<ChatMessage> galleryFromMessages(List<ChatMessage> messages) {
    final images = messages.where(isImageMessage).toList();
    images.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return images;
  }

  static bool isImageMessage(ChatMessage msg) {
    if (msg.type == 'image') return true;
    if (MediaLocalCache.localKind(msg.plaintext) == 'image') return true;
    final att = AttachmentPayload.fromPlaintext(msg.plaintext);
    if (att == null) return false;
    if (att.kind == 'image') return true;
    if (att.mime.startsWith('image/')) return true;
    return MediaSave.isImageName(att.name);
  }

  static ImageViewerPageData pageDataFor(
    ChatMessage msg, {
    MediaPayload? fallbackPreview,
    MediaRetryCallback? onMediaRetry,
  }) {
    final preview = _previewFor(msg, fallbackPreview);
    final previewBytes = _previewBytes(preview);
    final alreadyFull = previewBytes != null &&
        MediaLocalCache.hasFullImageBytes(
          previewBytes.length,
          msg.plaintext,
        );

    return ImageViewerPageData(
      bytes: previewBytes,
      onDownloadIfNeeded: alreadyFull || onMediaRetry == null
          ? null
          : ({onProgress}) =>
              onMediaRetry(msg.id, onProgress: onProgress),
      name: _displayName(msg, preview),
      messageId: msg.id,
      expectedPlaintext: msg.plaintext,
      fileId: msg.fileId,
    );
  }

  static String _displayName(ChatMessage msg, MediaPayload? fallbackPreview) {
    final preview = _previewFor(msg, fallbackPreview);
    return preview?.name.isNotEmpty == true ? preview!.name : 'image.jpg';
  }

  static MediaPayload? _previewFor(
    ChatMessage msg,
    MediaPayload? fallbackPreview,
  ) {
    final sync = MediaLocalCache.resolvePreviewSync(
      msg.plaintext,
      messageId: msg.id,
    );
    return sync ?? fallbackPreview;
  }

  static Uint8List? _previewBytes(MediaPayload? preview) {
    if (preview == null || preview.bytes.isEmpty) return null;
    return Uint8List.fromList(preview.bytes);
  }
}
