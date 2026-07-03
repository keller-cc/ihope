import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/media_download_index.dart';
import '../utils/media_save.dart';

class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    Uint8List? bytes,
    Future<Uint8List> Function()? bytesFuture,
    this.onRetryLoad,
    required this.name,
    this.messageId,
  })  : assert(bytes != null || bytesFuture != null || onRetryLoad != null),
        _bytes = bytes,
        _bytesFuture = bytesFuture;

  final Uint8List? _bytes;
  final Future<Uint8List> Function()? _bytesFuture;
  final Future<Uint8List> Function()? onRetryLoad;
  final String name;
  final String? messageId;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  Uint8List? _bytes;
  bool _loading = false;
  String? _loadError;
  bool _saving = false;
  double _progress = 0;
  String? _savedLabel;

  @override
  void initState() {
    super.initState();
    if (widget._bytes != null) {
      _bytes = widget._bytes;
    } else {
      _loading = true;
      unawaited(_loadBytes());
    }
    unawaited(_restoreSavedState());
  }

  Future<void> _loadBytes() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final loader = widget._bytesFuture ?? widget.onRetryLoad;
      if (loader == null) throw StateError('无法加载原图');
      final bytes = await loader();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restoreSavedState() async {
    final id = widget.messageId;
    if (id == null) return;
    final record = await MediaDownloadIndex.lookup(id);
    if (!mounted || record == null) return;
    setState(() => _savedLabel = record.displayLabel);
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null || _saving || _savedLabel != null) return;
    final id = widget.messageId;
    setState(() {
      _saving = true;
      _progress = 0;
    });
    try {
      final result = id != null
          ? await MediaDownloadIndex.saveForMessage(
              messageId: id,
              bytes: bytes,
              name: widget.name.isEmpty ? 'image.jpg' : widget.name,
              forceGallery: true,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
            )
          : await MediaSave.saveMedia(
              bytes: bytes,
              name: widget.name.isEmpty ? 'image.jpg' : widget.name,
              forceGallery: true,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
            );
      if (!mounted) return;
      setState(() {
        _savedLabel = result.displayLabel;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MediaSave.snackBarFor(result)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedLabel != null;
    final bytes = _bytes;
    final canRetry = widget.onRetryLoad != null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('原图', style: TextStyle(fontSize: 16)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('正在加载原图…', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '原图加载失败',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    if (canRetry) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _loading ? null : () => unawaited(_loadBytes()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('查看原图'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (bytes != null)
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          if (_saving)
            Positioned(
              left: 24,
              right: 24,
              bottom: 96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '正在保存… ${(_progress * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          if (bytes != null)
            Positioned(
              right: 20,
              bottom: 28,
              child: Material(
                color: saved
                    ? Colors.green.shade600
                    : Colors.white.withValues(alpha: 0.92),
                elevation: 4,
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  onTap: _saving || saved ? null : _save,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_saving)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            saved ? Icons.check : Icons.download_rounded,
                            color: saved ? Colors.white : Colors.black87,
                            size: 22,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          saved ? '已保存' : '保存原图',
                          style: TextStyle(
                            color: saved ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
