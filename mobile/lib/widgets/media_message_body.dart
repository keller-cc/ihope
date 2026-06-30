import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../models/message.dart';
import '../utils/media_local_cache.dart';
import '../utils/media_download_index.dart';
import '../utils/media_payload.dart';
import '../utils/media_save.dart';
import 'image_viewer_screen.dart';
import 'voice_message_bubble.dart';

enum _FileSaveState { idle, saving, saved }

enum _MediaLoadState { loading, ready, failed }

class MediaMessageBody extends StatefulWidget {
  const MediaMessageBody({
    super.key,
    required this.msg,
    required this.mine,
    this.initialMedia,
    this.onMediaRetry,
  });

  final ChatMessage msg;
  final bool mine;
  final MediaPayload? initialMedia;
  final Future<void> Function(String messageId)? onMediaRetry;

  @override
  State<MediaMessageBody> createState() => _MediaMessageBodyState();
}

class _MediaMessageBodyState extends State<MediaMessageBody> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _paused = false;
  int _positionMs = 0;
  _FileSaveState _fileState = _FileSaveState.idle;
  double _saveProgress = 0;
  String? _savedPath;
  String? _savedLabel;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _positionSub;
  MediaPayload? _media;
  _MediaLoadState _loadState = _MediaLoadState.loading;

  @override
  void initState() {
    super.initState();
    if (widget.initialMedia != null) {
      _media = widget.initialMedia;
      _loadState = _MediaLoadState.ready;
    }
    unawaited(_loadMedia());
    unawaited(_restoreSavedState());
  }

  @override
  void didUpdateWidget(MediaMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.msg.id != widget.msg.id ||
        oldWidget.msg.plaintext != widget.msg.plaintext) {
      _media = widget.initialMedia;
      _loadState =
          _media != null ? _MediaLoadState.ready : _MediaLoadState.loading;
      unawaited(_loadMedia());
    }
  }

  Future<void> _retryLoadMedia() async {
    if (_loadState == _MediaLoadState.failed &&
        widget.onMediaRetry != null) {
      await widget.onMediaRetry!(widget.msg.id);
      if (!mounted) return;
    }
    await _loadMedia();
  }

  Future<void> _loadMedia() async {
    if (!mounted) return;
    if (_media == null) {
      setState(() => _loadState = _MediaLoadState.loading);
    }
    final resolved = await MediaLocalCache.resolve(
      widget.msg.id,
      widget.msg.plaintext,
    );
    if (!mounted) return;
    if (resolved != null && resolved.bytes.isNotEmpty) {
      setState(() {
        _media = resolved;
        _loadState = _MediaLoadState.ready;
      });
    } else {
      setState(() => _loadState = _MediaLoadState.failed);
    }
  }

  int _durationSecondsFallback() {
    final fromMedia = _media?.durationMs ??
        MediaLocalCache.durationMsFromPlaintext(widget.msg.plaintext);
    return math.max(1, ((fromMedia ?? 0) / 1000).round());
  }

  Future<void> _restoreSavedState() async {
    if (_media?.kind != 'file') return;
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
    VoicePlaybackHub.release(widget.msg.id);
    _completeSub?.cancel();
    _positionSub?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  Uint8List get _bytes => Uint8List.fromList(_media?.bytes ?? const []);

  int get _totalSeconds => math.max(
        1,
        ((_media?.durationMs ?? 0) / 1000).round(),
      );

  Future<void> _stopPlayback({bool notifyHub = true}) async {
    await _player.stop();
    _completeSub?.cancel();
    _completeSub = null;
    _positionSub?.cancel();
    _positionSub = null;
    if (notifyHub) VoicePlaybackHub.release(widget.msg.id);
    if (mounted) {
      setState(() {
        _playing = false;
        _paused = false;
        _positionMs = 0;
      });
    }
  }

  void _attachPlayerListeners() {
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      unawaited(_stopPlayback());
    });
    _positionSub?.cancel();
    _positionSub = _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _positionMs = pos.inMilliseconds);
    });
  }

  Future<void> _toggleAudio() async {
    if (_media == null || _loadState != _MediaLoadState.ready) {
      await _loadMedia();
      return;
    }
    if (_bytes.isEmpty) return;
    if (_playing) {
      await _player.pause();
      if (mounted) {
        setState(() {
          _playing = false;
          _paused = true;
        });
      }
      return;
    }
    if (_paused) {
      VoicePlaybackHub.claim(widget.msg.id, () {
        unawaited(_stopPlayback());
      });
      await _player.resume();
      if (mounted) {
        setState(() {
          _playing = true;
          _paused = false;
        });
      }
      return;
    }
    VoicePlaybackHub.claim(widget.msg.id, () {
      unawaited(_stopPlayback());
    });
    await _player.play(BytesSource(_bytes));
    _attachPlayerListeners();
    if (mounted) {
      setState(() {
        _playing = true;
        _paused = false;
        _positionMs = 0;
      });
    }
  }

  Future<void> _openImage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          bytes: _bytes,
          name: _media?.name ?? 'image.jpg',
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
    final media = _media;
    if (media == null) return;
    setState(() {
      _fileState = _FileSaveState.saving;
      _saveProgress = 0;
    });
    try {
      final result = await MediaDownloadIndex.saveForMessage(
        messageId: widget.msg.id,
        bytes: media.bytes,
        name: media.name,
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
    final size = _formatSize(_media?.bytes.length ?? 0);
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
    final media = _media;
    if (_loadState == _MediaLoadState.loading && media == null) {
      return const SizedBox(
        width: 96,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (media == null || _loadState == _MediaLoadState.failed) {
      final kind = MediaLocalCache.localKind(widget.msg.plaintext) ??
          widget.msg.type;
      if (kind == 'audio') {
        return Opacity(
          opacity: 0.75,
          child: VoiceMessageBubble(
            messageId: widget.msg.id,
            mine: widget.mine,
            totalSeconds: _durationSecondsFallback(),
            playing: false,
            positionMs: 0,
            onTap: () => unawaited(_retryLoadMedia()),
          ),
        );
      }
      return InkWell(
        onTap: () => unawaited(_retryLoadMedia()),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            MediaPayload.previewFromPlaintext(
              widget.msg.plaintext,
              widget.msg.type,
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
      );
    }
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
        return VoiceMessageBubble(
          messageId: widget.msg.id,
          mine: widget.mine,
          totalSeconds: _totalSeconds,
          playing: _playing,
          positionMs: _positionMs,
          onTap: () => unawaited(_toggleAudio()),
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

