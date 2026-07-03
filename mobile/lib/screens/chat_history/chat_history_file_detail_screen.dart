import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../utils/file_size_format.dart';
import '../../utils/media_local_cache.dart';
import '../../utils/media_payload.dart';

/// 文件详情 / 下载。
class ChatHistoryFileDetailScreen extends StatefulWidget {
  const ChatHistoryFileDetailScreen({
    super.key,
    required this.auth,
    required this.conversation,
    required this.message,
    required this.senderName,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final ChatMessage message;
  final String senderName;

  @override
  State<ChatHistoryFileDetailScreen> createState() =>
      _ChatHistoryFileDetailScreenState();
}

class _ChatHistoryFileDetailScreenState
    extends State<ChatHistoryFileDetailScreen> {
  bool _downloading = false;
  double _progress = 0;
  bool _ready = false;

  MediaPayload? get _media => MediaPayload.tryParse(widget.message.plaintext);

  @override
  void initState() {
    super.initState();
    unawaited(_checkReady());
  }

  Future<void> _checkReady() async {
    final ready = await MediaLocalCache.hasPayloadFile(widget.message.id);
    if (!mounted) return;
    setState(() => _ready = ready);
    if (ready) unawaited(_openFile());
  }

  Future<void> _openFile() async {
    final path = await MediaLocalCache.openablePath(widget.message.id);
    if (path == null) return;
    await OpenFile.open(path);
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      var msg = widget.message;
      if (!await MediaLocalCache.hasPayloadFile(msg.id)) {
        msg = await widget.auth.decryptMessage(widget.conversation, msg);
        final pt = msg.plaintext;
        if (pt != null) {
          await MediaLocalCache.persistPlaintext(msg.id, pt);
        }
      }
      final resolved = await MediaLocalCache.resolve(msg.id, msg.plaintext);
      if (resolved == null) throw StateError('无法解析文件');
      await MediaLocalCache.persistPlaintext(msg.id, msg.plaintext ?? '');
      if (!mounted) return;
      setState(() {
        _ready = true;
        _downloading = false;
      });
      await _openFile();
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    }
  }

  IconData _iconFor() {
    final media = _media;
    final name = media?.name ?? '';
    final mime = media?.mime ?? '';
    final lower = '$mime $name'.toLowerCase();
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = _media;
    final name = media?.name ?? '文件';
    final size = media?.bytes.length ?? 0;
    final sizeLabel = FileSizeFormat.format(size);

    return Scaffold(
      appBar: AppBar(title: const Text('文件')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_iconFor(), size: 72, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                sizeLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '来自 ${widget.senderName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              if (_downloading) ...[
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                ),
                const SizedBox(height: 12),
                const Text('正在下载…'),
              ] else if (_ready)
                FilledButton.icon(
                  onPressed: _openFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开文件'),
                )
              else
                FilledButton(
                  onPressed: _download,
                  child: Text('下载($sizeLabel)'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
