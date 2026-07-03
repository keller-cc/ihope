import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../utils/file_size_format.dart';
import '../../utils/media_payload.dart';
import '../../utils/message_time.dart';
import '../../utils/text_search.dart';
import 'chat_history_file_detail_screen.dart';
import 'chat_history_loader.dart';

/// 文件 Tab。
class ChatHistoryFilesTab extends StatefulWidget {
  const ChatHistoryFilesTab({
    super.key,
    required this.auth,
    required this.conversation,
    required this.messages,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final List<ChatMessage> messages;

  @override
  State<ChatHistoryFilesTab> createState() => _ChatHistoryFilesTabState();
}

class _ChatHistoryFilesTabState extends State<ChatHistoryFilesTab> {
  final _search = TextEditingController();
  late final List<ChatMessage> _files;

  @override
  void initState() {
    super.initState();
    _files = ChatHistoryLoader.filterFiles(widget.messages);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChatMessage> get _filtered {
    final q = _search.text.trim();
    if (q.isEmpty) return _files;
    return _files.where((m) {
      final media = MediaPayload.tryParse(m.plaintext);
      final name = media?.name ?? '';
      return textMatchesQuery(name, q) ||
          textMatchesQuery(_senderName(m.senderId), q);
    }).toList();
  }

  String _senderName(String userId) {
    final me = widget.auth.currentUser!;
    if (userId == me.id) return me.username;
    return widget.auth.groupMemberUsername(widget.conversation, userId);
  }

  String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  IconData _iconFor(String? mime, String name) {
    final lower = '${mime ?? ''} $name'.toLowerCase();
    if (lower.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (lower.contains('zip') || lower.contains('rar')) return Icons.folder_zip_outlined;
    if (lower.contains('doc')) return Icons.description_outlined;
    if (lower.contains('xls')) return Icons.table_chart_outlined;
    return Icons.insert_drive_file_outlined;
  }

  void _openFile(ChatMessage msg) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatHistoryFileDetailScreen(
          auth: widget.auth,
          conversation: widget.conversation,
          message: msg,
          senderName: _senderName(msg.senderId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索文件名或发送者',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('暂无文件'))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final msg = list[index];
                    final media = MediaPayload.tryParse(msg.plaintext);
                    final name = media?.name ?? '文件';
                    final size = media?.bytes.length ?? 0;
                    final time = MessageTimeFormat.formatList(msg.createdAt);
                    final from = _truncate(_senderName(msg.senderId), 8);

                    return ListTile(
                      leading: Icon(
                        _iconFor(media?.mime, name),
                        size: 36,
                        color: scheme.primary,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('$time · 来自$from · ${FileSizeFormat.format(size)}'),
                      onTap: () => _openFile(msg),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
