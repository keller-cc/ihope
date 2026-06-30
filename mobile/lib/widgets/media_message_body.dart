import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../models/message.dart';
import '../utils/media_download_index.dart';
import '../utils/media_payload.dart';
import '../utils/media_save.dart';
import 'image_viewer_screen.dart';

enum _FileSaveState { idle, saving, saved }

class MediaMessageBody extends StatefulWidget {
  const MediaMessageBody({
    super.key,
    required this.msg,
    required this.media,
    required this.mine,
  });

  final ChatMessage msg;
  final MediaPayload media;
  final bool mine;

  @override
  State<MediaMessageBody> createState() => _MediaMessageBodyState();
}

class _MediaMessageBodyState extends State<MediaMessageBody> {
  final _player = AudioPlayer();
  bool _playing = false;
  _FileSaveState _fileState = _FileSaveState.idle;
  double _saveProgress = 0;
  String? _savedPath;
  String? _savedLabel;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSavedState());
  }

  Future<void> _restoreSavedState() async {
    if (widget.media.kind != 'file') return;
    final record = await MediaDownloadIndex.lookup(widget.msg.id);
    if (!mounted || record == null) return;
    setState(() {
      _fileState = _FileSaveState.saved;
      _savedPath = record.openPath;
      _savedLabel = record.displayLabel;
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Uint8List get _bytes => Uint8List.fromList(widget.media.bytes);

  Future<void> _toggleAudio() async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(BytesSource(_bytes));
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    if (mounted) setState(() => _playing = true);
  }

  Future<void> _openImage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          bytes: _bytes,
          name: widget.media.name,
          messageId: widget.msg.id,
        ),
      ),
    );
  }

  Future<void> _onFileTap() async {
    if (_fileState == _FileSaveState.saving) return;
    if (_fileState == _FileSaveState.saved && _savedPath != null) {
      final result = await MediaSave.openPath(_savedPath!);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法打开，文件位于 ${MediaSave.displayPath(_savedPath!)}'),
          ),
        );
      }
      return;
    }
    await _saveFile();
  }

  Future<void> _saveFile() async {
    setState(() {
      _fileState = _FileSaveState.saving;
      _saveProgress = 0;
    });
    try {
      final result = await MediaDownloadIndex.saveForMessage(
        messageId: widget.msg.id,
        bytes: widget.media.bytes,
        name: widget.media.name,
        onProgress: (p) {
          if (mounted) setState(() => _saveProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _fileState = _FileSaveState.saved;
        _savedPath = result.openPath;
        _savedLabel = result.displayLabel;
        _saveProgress = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MediaSave.snackBarFor(result)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fileState = _FileSaveState.idle);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fileSubtitle() {
    final size = _formatSize(widget.media.bytes.length);
    switch (_fileState) {
      case _FileSaveState.idle:
        return '$size · 点击下载到本地';
      case _FileSaveState.saving:
        return '正在下载… ${(_saveProgress * 100).round()}%';
      case _FileSaveState.saved:
        final hint = _savedLabel ??
            (_savedPath != null ? MediaSave.displayPath(_savedPath!) : '本地');
        return '$size · 已保存至 $hint · 点击打开';
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    switch (media.kind) {
      case 'image':
        return GestureDetector(
          onTap: _openImage,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 220,
              maxHeight: 280,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      case 'audio':
        return _VoiceBubble(
          mine: widget.mine,
          seconds: math.max(
            1,
            ((media.durationMs ?? 0) / 1000).round(),
          ),
          playing: _playing,
          onTap: _toggleAudio,
        );
      case 'file':
      default:
        return InkWell(
          onTap: () => unawaited(_onFileTap()),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _fileState == _FileSaveState.saved
                          ? Icons.task_outlined
                          : Icons.insert_drive_file_outlined,
                      size: 32,
                      color: _fileState == _FileSaveState.saved
                          ? Colors.green.shade600
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        media.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                if (_fileState == _FileSaveState.saving) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _saveProgress > 0 ? _saveProgress : null,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _fileSubtitle(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// 微信风格语音条：宽度随秒数变化，显示 N″。
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.mine,
    required this.seconds,
    required this.playing,
    required this.onTap,
  });

  final bool mine;
  final int seconds;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const minW = 72.0;
    const maxW = 200.0;
    final width = minW + (maxW - minW) * (seconds.clamp(1, 60) / 60.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: width,
          height: 36,
          child: Row(
            mainAxisAlignment:
                mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!mine) ...[
                _VoiceWaveIcon(playing: playing, mine: mine),
                const SizedBox(width: 8),
              ],
              Text(
                '$seconds″',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 8),
                _VoiceWaveIcon(playing: playing, mine: mine),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 微信风格 WiFi 形声波图标。
class _VoiceWaveIcon extends StatelessWidget {
  const _VoiceWaveIcon({required this.playing, required this.mine});

  final bool playing;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 18),
      painter: _VoiceWavePainter(
        playing: playing,
        flip: mine,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  _VoiceWavePainter({
    required this.playing,
    required this.flip,
    required this.color,
  });

  final bool playing;
  final bool flip;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    canvas.save();
    if (flip) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }

    final ox = 2.0;
    final oy = size.height / 2;

    canvas.drawLine(Offset(ox, oy - 3), Offset(ox, oy + 3), paint);

    if (playing) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(ox, oy), radius: 5),
        -math.pi / 3,
        math.pi * 2 / 3,
        false,
        paint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset(ox, oy), radius: 9),
        -math.pi / 3,
        math.pi * 2 / 3,
        false,
        paint,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(ox, oy), radius: 6),
        -math.pi / 3,
        math.pi * 2 / 3,
        false,
        paint,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter oldDelegate) {
    return oldDelegate.playing != playing ||
        oldDelegate.flip != flip ||
        oldDelegate.color != color;
  }
}
