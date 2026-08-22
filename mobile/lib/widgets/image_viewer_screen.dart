import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/media_download_index.dart';
import '../utils/media_local_cache.dart';
import '../utils/media_retry_callback.dart';
import '../utils/media_save.dart';

/// 单张图片的查看参数。
class ImageViewerPageData {
  const ImageViewerPageData({
    this.bytes,
    this.onDownloadIfNeeded,
    required this.name,
    this.messageId,
    this.expectedPlaintext,
    this.fileId,
  });

  final Uint8List? bytes;
  final MediaDownloadCallback? onDownloadIfNeeded;
  final String name;
  final String? messageId;
  final String? expectedPlaintext;
  final String? fileId;
}

/// 全屏看图（QQ/微信风格）：黑底、顶部返回、底部保存、左右滑动多图。
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.pages,
    this.initialIndex = 0,
  }) : assert(pages.length > 0);

  final List<ImageViewerPageData> pages;
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pageController;
  late int _index;
  late final List<GlobalKey<_ImageViewerContentState>> _pageKeys;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.pages.length - 1);
    _pageController = PageController(initialPage: _index);
    _pageKeys = List.generate(
      widget.pages.length,
      (_) => GlobalKey<_ImageViewerContentState>(),
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  _ImageViewerContentState? get _currentPage => _pageKeys[_index].currentState;

  @override
  Widget build(BuildContext context) {
    final page = _currentPage;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.pages.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              return _ImageViewerContent(
                key: _pageKeys[i],
                data: widget.pages[i],
                onChanged: () {
                  if (mounted) setState(() {});
                },
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          if (page != null && page.hasImage)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _WeChatStyleBottomBar(
                  saving: page.saving,
                  saved: page.saved,
                  onSave: page.saving || page.saved
                      ? null
                      : () => unawaited(page.save()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 底部操作条（与微信「保存图片」一致：图标 + 文案）。
class _WeChatStyleBottomBar extends StatelessWidget {
  const _WeChatStyleBottomBar({
    required this.saving,
    required this.saved,
    this.onSave,
  });

  final bool saving;
  final bool saved;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: onSave,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (saving)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  else
                    Icon(
                      saved ? Icons.check_circle_outline : Icons.download_outlined,
                      color: saved ? Colors.white54 : Colors.white,
                      size: 28,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    saved ? '已保存' : '保存图片',
                    style: TextStyle(
                      color: saved ? Colors.white54 : Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageViewerContent extends StatefulWidget {
  const _ImageViewerContent({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final ImageViewerPageData data;
  final VoidCallback onChanged;

  @override
  State<_ImageViewerContent> createState() => _ImageViewerContentState();
}

class _ImageViewerContentState extends State<_ImageViewerContent> {
  Uint8List? _bytes;
  bool _loadError = false;
  bool _saving = false;
  String? _savedLabel;

  ImageViewerPageData get data => widget.data;

  bool get hasImage => _bytes != null;
  bool get saving => _saving;
  bool get saved => _savedLabel != null;

  bool _isFullBytes(Uint8List bytes) =>
      MediaLocalCache.hasFullImageBytes(bytes.length, data.expectedPlaintext);

  bool get _canRetry =>
      data.onDownloadIfNeeded != null || data.messageId != null;

  @override
  void initState() {
    super.initState();
    final initial = data.bytes;
    if (initial != null && initial.isNotEmpty) {
      _bytes = initial;
    }
    if (_bytes != null && _isFullBytes(_bytes!)) {
      unawaited(_restoreSavedState());
      return;
    }
    unawaited(_resolveFullInBackground());
  }

  @override
  void didUpdateWidget(covariant _ImageViewerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.messageId != data.messageId) {
      _bytes = data.bytes;
      _loadError = false;
      _savedLabel = null;
      unawaited(_resolveFullInBackground());
      unawaited(_restoreSavedState());
    }
  }

  Future<void> _resolveFullInBackground() async {
    final local = await _tryLoadLocalFull();
    if (local != null) {
      if (!mounted) return;
      setState(() {
        _bytes = local;
        _loadError = false;
      });
      widget.onChanged();
      unawaited(_restoreSavedState());
      return;
    }

    if (data.onDownloadIfNeeded != null) {
      await _upgradeToFullSilently();
    }
    unawaited(_restoreSavedState());
  }

  Future<Uint8List?> _tryLoadLocalFull() async {
    final id = data.messageId;
    if (id == null) return null;
    return MediaLocalCache.tryLoadFullImageBytes(
      messageId: id,
      plaintext: data.expectedPlaintext,
      fileId: data.fileId,
    );
  }

  Future<Uint8List> _resolveFullBytes() async {
    final id = data.messageId;
    if (id != null) {
      return MediaLocalCache.resolveFullImageBytes(
        messageId: id,
        plaintext: data.expectedPlaintext,
        fileId: data.fileId,
        downloadIfNeeded: data.onDownloadIfNeeded,
      );
    }
    if (data.onDownloadIfNeeded == null) {
      throw StateError('无法加载原图');
    }
    await data.onDownloadIfNeeded!();
    final local = await _tryLoadLocalFull();
    if (local != null) return local;
    throw StateError('原图不可用');
  }

  Future<void> _upgradeToFullSilently() async {
    final local = await _tryLoadLocalFull();
    if (local != null) {
      if (!mounted) return;
      setState(() {
        _bytes = local;
        _loadError = false;
      });
      widget.onChanged();
      return;
    }

    if (data.onDownloadIfNeeded == null && data.messageId == null) return;

    try {
      final bytes = await _resolveFullBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loadError = false;
      });
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      if (_bytes == null || _bytes!.isEmpty) {
        setState(() => _loadError = true);
        widget.onChanged();
      }
    }
  }

  Future<void> _restoreSavedState() async {
    final id = data.messageId;
    if (id == null) return;
    final record = await MediaDownloadIndex.lookup(id);
    if (!mounted || record == null) return;
    setState(() => _savedLabel = record.displayLabel);
    widget.onChanged();
  }

  Future<void> save() async {
    if (_saving || _savedLabel != null) return;
    final id = data.messageId;
    setState(() => _saving = true);
    widget.onChanged();
    try {
      final bytes = await _bytesForSave();
      if (!mounted) return;
      setState(() => _bytes = bytes);
      final result = id != null
          ? await MediaDownloadIndex.saveForMessage(
              messageId: id,
              bytes: bytes,
              name: data.name.isEmpty ? 'image.jpg' : data.name,
              forceGallery: true,
            )
          : await MediaSave.saveMedia(
              bytes: bytes,
              name: data.name.isEmpty ? 'image.jpg' : data.name,
              forceGallery: true,
            );
      if (!mounted) return;
      setState(() {
        _savedLabel = result.displayLabel;
        _saving = false;
      });
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MediaSave.snackBarFor(result)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<Uint8List> _bytesForSave() async {
    final current = _bytes;
    if (current != null && current.isNotEmpty && _isFullBytes(current)) {
      return current;
    }
    final local = await _tryLoadLocalFull();
    if (local != null) return local;
    final bytes = await _resolveFullBytes();
    if (!_isFullBytes(bytes)) {
      throw StateError('原图尚未下载完成');
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;

    if (_loadError && bytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '图片加载失败',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              if (_canRetry) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => unawaited(_upgradeToFullSilently()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (bytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.high,
          isAntiAlias: true,
        ),
      ),
    );
  }
}
