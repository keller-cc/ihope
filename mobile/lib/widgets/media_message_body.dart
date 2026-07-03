import 'dart:async';
import 'dart:convert';
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

enum _FileReceiveState { pending, receiving, received }

enum _FileExportState { none, exporting, exported }

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
  _FileReceiveState _fileRecv = _FileReceiveState.pending;
  _FileExportState _fileExport = _FileExportState.none;
  double _receiveProgress = 0;
  double _exportProgress = 0;
  String? _exportedPath;
  String? _exportedLabel;
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
    unawaited(_restoreFileState());
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
      final filePending = resolved.kind == 'file' &&
          widget.msg.fileId != null &&
          !await MediaLocalCache.hasPayloadFile(widget.msg.id);
      if (!mounted) return;
      setState(() {
        _media = resolved;
        _loadState = _MediaLoadState.ready;
        if (resolved.kind == 'file') {
          _fileRecv = filePending
              ? _FileReceiveState.pending
              : _FileReceiveState.received;
        }
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

  Future<void> _restoreFileState() async {
    if (widget.msg.type != 'file') return;
    if (widget.msg.fileId != null) {
      if (!mounted) return;
      setState(() => _fileRecv = _FileReceiveState.pending);
      return;
    }
    if (await MediaLocalCache.hasPayloadFile(widget.msg.id)) {
      if (mounted) setState(() => _fileRecv = _FileReceiveState.received);
    }
    final record = await MediaDownloadIndex.lookup(widget.msg.id);
    if (!mounted || record == null) return;
    setState(() {
      _fileExport = _FileExportState.exported;
      _exportedPath = record.openPath;
      _exportedLabel = record.displayLabel;
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
    var bytes = _bytes;
    if (widget.msg.fileId != null &&
        !await MediaLocalCache.hasPayloadFile(widget.msg.id)) {
      setState(() => _loadState = _MediaLoadState.loading);
      if (widget.onMediaRetry != null) {
        await widget.onMediaRetry!(widget.msg.id);
      }
      await _loadMedia();
      bytes = _bytes;
    }
    if (bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片加载失败，请重试')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          bytes: bytes,
          name: _media?.name ?? 'image.jpg',
          messageId: widget.msg.id,
        ),
      ),
    );
  }

  Future<void> _onFileTap() async {
    if (_fileRecv == _FileReceiveState.receiving) return;
    if (_fileRecv == _FileReceiveState.pending) {
      await _receiveFile();
      return;
    }
    await _openReceivedFile();
  }

  Future<void> _receiveFile() async {
    setState(() {
      _fileRecv = _FileReceiveState.receiving;
      _receiveProgress = 0;
    });
    try {
      if (widget.onMediaRetry != null) {
        await widget.onMediaRetry!(widget.msg.id);
      }
      await _loadMedia();
      if (!mounted) return;
      if (_media == null) {
        setState(() => _fileRecv = _FileReceiveState.pending);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('接收失败，请重试')),
        );
        return;
      }
      setState(() => _fileRecv = _FileReceiveState.received);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fileRecv = _FileReceiveState.pending);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('接收失败：$e')),
      );
    }
  }

  Future<void> _openReceivedFile() async {
    final path = await MediaLocalCache.openablePath(widget.msg.id);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件不存在，请重新接收')),
      );
      setState(() => _fileRecv = _FileReceiveState.pending);
      return;
    }
    final result = await MediaSave.openPath(path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开：${MediaSave.displayPath(path)}')),
      );
    }
  }

  Future<void> _exportFileToPhone() async {
    if (_fileExport == _FileExportState.exporting) return;
    if (_fileRecv != _FileReceiveState.received || _media == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先接收文件')),
      );
      return;
    }
    if (_fileExport == _FileExportState.exported) {
      final path = _exportedPath;
      if (path != null) {
        await MediaSave.openPath(path);
      }
      return;
    }
    final media = _media!;
    setState(() {
      _fileExport = _FileExportState.exporting;
      _exportProgress = 0;
    });
    try {
      final result = await MediaDownloadIndex.saveForMessage(
        messageId: widget.msg.id,
        bytes: media.bytes,
        name: media.name,
        onProgress: (p) {
          if (mounted) setState(() => _exportProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _fileExport = _FileExportState.exported;
        _exportedPath = result.openPath;
        _exportedLabel = result.displayLabel;
        _exportProgress = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MediaSave.snackBarFor(result)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _fileExport = _FileExportState.none);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
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

  String _fileDisplayName() {
    if (_media != null) return _media!.name;
    try {
      final map = widget.msg.plaintext != null
          ? (jsonDecode(widget.msg.plaintext!) as Map<String, dynamic>)
          : null;
      if (map != null && map['name'] is String) return map['name'] as String;
    } catch (_) {}
    final att = AttachmentPayload.tryParse(widget.msg.plaintext);
    if (att != null) return att.name;
    return '文件';
  }

  String _fileSubtitle() {
    switch (_fileRecv) {
      case _FileReceiveState.pending:
        return '点击接收文件';
      case _FileReceiveState.receiving:
        return '正在接收…';
      case _FileReceiveState.received:
        final size = _media != null ? _formatSize(_media!.bytes.length) : '';
        final exportHint = _fileExport == _FileExportState.exported
            ? ' · 已保存至 ${_exportedLabel ?? '手机'}'
            : '';
        return size.isEmpty
            ? '点击打开$exportHint'
            : '$size · 点击打开$exportHint';
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
          AttachmentPayload.tryParse(widget.msg.plaintext)?.kind ??
          widget.msg.type;
      if (kind == 'file') {
        return _buildFileCard(pending: true);
      }
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
        return _buildFileCard(pending: false);
    }
  }

  Widget _buildFileCard({required bool pending}) {
    final receiving = _fileRecv == _FileReceiveState.receiving;
    final received = _fileRecv == _FileReceiveState.received;
    return InkWell(
      onTap: () => unawaited(_onFileTap()),
      onLongPress: received ? () => unawaited(_exportFileToPhone()) : null,
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
                  received
                      ? Icons.insert_drive_file_outlined
                      : Icons.file_download_outlined,
                  size: 32,
                  color: received ? null : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    pending && !received ? '文件' : _fileDisplayName(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (received)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    tooltip: _fileExport == _FileExportState.exported
                        ? '打开已保存副本'
                        : '保存到手机',
                    onPressed: _fileExport == _FileExportState.exporting
                        ? null
                        : () => unawaited(_exportFileToPhone()),
                    icon: Icon(
                      _fileExport == _FileExportState.exported
                          ? Icons.folder_outlined
                          : Icons.download_outlined,
                      size: 20,
                    ),
                  ),
              ],
            ),
            if (receiving || _fileExport == _FileExportState.exporting) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: receiving
                    ? (_receiveProgress > 0 ? _receiveProgress : null)
                    : (_exportProgress > 0 ? _exportProgress : null),
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

