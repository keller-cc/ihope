import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../utils/media_local_cache.dart';
import '../../screens/chat/chat_image_launcher.dart';
import 'chat_history_loader.dart';

/// 图片/视频 Tab：按年月分组，每行 4 张。
class ChatHistoryMediaTab extends StatefulWidget {
  const ChatHistoryMediaTab({
    super.key,
    required this.auth,
    required this.conversation,
    required this.messages,
  });

  final AuthService auth;
  final ConversationItem conversation;
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
    if (!mounted) return;
    await ChatImageLauncher.open(
      context,
      msg,
      imageGallery: widget.messages,
      onMediaRetry: (messageId, {onProgress}) async {
        final target = widget.messages.firstWhere(
          (m) => m.id == messageId,
          orElse: () => msg,
        );
        final repaired = await widget.auth.repairMessageMedia(
          widget.conversation,
          target,
          onProgress: onProgress,
        );
        if (repaired == null) throw StateError('无法下载原图');
      },
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
                style: Theme.of(context).textTheme.titleSmall,
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
                  return _MediaThumb(
                    msg: msg,
                    onTap: () => unawaited(_openImage(msg)),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.msg, required this.onTap});

  final ChatMessage msg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sync = MediaLocalCache.resolvePreviewSync(
      msg.plaintext,
      messageId: msg.id,
    );
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: sync != null && sync.bytes.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  Uint8List.fromList(sync.bytes),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  gaplessPlayback: true,
                ),
              )
            : const Center(
                child: Icon(Icons.image_outlined, size: 28),
              ),
      ),
    );
  }
}
