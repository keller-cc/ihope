import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../utils/media_local_cache.dart';
import '../../widgets/image_viewer_screen.dart';
import 'chat_history_loader.dart';

/// 图片/视频 Tab：按年月分组，每行 4 张。
class ChatHistoryMediaTab extends StatefulWidget {
  const ChatHistoryMediaTab({
    super.key,
    required this.auth,
    required this.messages,
  });

  final AuthService auth;
  final List<ChatMessage> messages;

  @override
  State<ChatHistoryMediaTab> createState() => _ChatHistoryMediaTabState();
}

class _ChatHistoryMediaTabState extends State<ChatHistoryMediaTab> {
  late final List<ChatMessage> _images;
  late final Map<String, List<ChatMessage>> _groups;
  late final List<String> _keys;

  @override
  void initState() {
    super.initState();
    _images = ChatHistoryLoader.filterImages(widget.messages);
    _groups = ChatHistoryLoader.groupByYearMonth(_images);
    _keys = _groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Future<void> _openImage(ChatMessage msg) async {
    final resolved = await MediaLocalCache.resolve(msg.id, msg.plaintext);
    if (!mounted) return;
    if (resolved == null || resolved.bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片尚未缓存，请先在会话中查看')),
      );
      return;
    }
    final name = resolved.name.isNotEmpty ? resolved.name : 'image.jpg';
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          bytes: Uint8List.fromList(resolved.bytes),
          name: name,
          messageId: msg.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_images.isEmpty) {
      return const Center(child: Text('暂无图片或视频'));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _keys.length,
      itemBuilder: (context, index) {
        final key = _keys[index];
        final items = _groups[key]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                key,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final msg = items[i];
                  return _MediaThumb(msg: msg, onTap: () => _openImage(msg));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaThumb extends StatefulWidget {
  const _MediaThumb({required this.msg, required this.onTap});

  final ChatMessage msg;
  final VoidCallback onTap;

  @override
  State<_MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<_MediaThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final resolved =
        await MediaLocalCache.resolve(widget.msg.id, widget.msg.plaintext);
    if (!mounted || resolved == null) return;
    setState(() => _bytes = Uint8List.fromList(resolved.bytes));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: widget.onTap,
        child: _bytes != null
            ? Image.memory(_bytes!, fit: BoxFit.cover)
            : Center(
                child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
              ),
      ),
    );
  }
}
