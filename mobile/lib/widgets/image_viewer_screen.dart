import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../utils/media_download_index.dart';
import '../utils/media_save.dart';

class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.bytes,
    required this.name,
    this.messageId,
  });

  final Uint8List bytes;
  final String name;
  final String? messageId;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _saving = false;
  double _progress = 0;
  String? _savedLabel;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSavedState());
  }

  Future<void> _restoreSavedState() async {
    final id = widget.messageId;
    if (id == null) return;
    final record = await MediaDownloadIndex.lookup(id);
    if (!mounted || record == null) return;
    setState(() => _savedLabel = record.displayLabel);
  }

  Future<void> _save() async {
    if (_saving || _savedLabel != null) return;
    final id = widget.messageId;
    setState(() {
      _saving = true;
      _progress = 0;
    });
    try {
      final result = id != null
          ? await MediaDownloadIndex.saveForMessage(
              messageId: id,
              bytes: widget.bytes,
              name: widget.name.isEmpty ? 'image.jpg' : widget.name,
              forceGallery: true,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
            )
          : await MediaSave.saveMedia(
              bytes: widget.bytes,
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

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(widget.bytes, fit: BoxFit.contain),
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
                        saved ? '已保存' : '保存',
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
