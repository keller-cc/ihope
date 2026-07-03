import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../services/auth_service.dart';
import 'chat_history_category_screen.dart';
import 'chat_history_jump.dart';
import 'chat_history_loader.dart';
import 'chat_history_search_screen.dart';

/// 查找聊天记录入口：顶部搜索框 + 中部分类按钮。
class ChatHistoryHubScreen extends StatefulWidget {
  const ChatHistoryHubScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<ChatHistoryHubScreen> createState() => _ChatHistoryHubScreenState();
}

class _ChatHistoryHubScreenState extends State<ChatHistoryHubScreen> {
  late final ChatHistoryLoader _loader;

  bool get _isGroup => widget.conversation.type == 'group';

  @override
  void initState() {
    super.initState();
    _loader = ChatHistoryLoader(
      auth: widget.auth,
      conversation: widget.conversation,
    );
    // 后台预加载，进入分类页时更快；主界面不阻塞。
    unawaited(_loader.load());
  }

  void _jumpToMessage(String? messageId) {
    Navigator.of(context).pop(ChatHistoryJump(messageId: messageId));
  }

  Future<void> _openSearch() async {
    final jump = await Navigator.of(context).push<ChatHistoryJump>(
      MaterialPageRoute(
        builder: (_) => ChatHistorySearchScreen(
          auth: widget.auth,
          conversation: widget.conversation,
          loader: _loader,
        ),
      ),
    );
    if (jump != null && mounted) _jumpToMessage(jump.messageId);
  }

  Future<void> _openCategory(ChatHistoryCategoryKind kind) async {
    final jump = await Navigator.of(context).push<ChatHistoryJump>(
      MaterialPageRoute(
        builder: (_) => ChatHistoryCategoryScreen(
          kind: kind,
          auth: widget.auth,
          conversation: widget.conversation,
          loader: _loader,
        ),
      ),
    );
    if (jump != null && mounted) _jumpToMessage(jump.messageId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('查找聊天记录')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            child: InkWell(
              onTap: _openSearch,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.search, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '搜索',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                _CategoryTile(
                  icon: Icons.calendar_today_outlined,
                  label: '日期',
                  onTap: () => _openCategory(ChatHistoryCategoryKind.date),
                ),
                if (_isGroup) ...[
                  const SizedBox(height: 12),
                  _CategoryTile(
                    icon: Icons.people_outline,
                    label: '群成员',
                    onTap: () => _openCategory(ChatHistoryCategoryKind.members),
                  ),
                ],
                const SizedBox(height: 12),
                _CategoryTile(
                  icon: Icons.photo_library_outlined,
                  label: '图片/视频',
                  onTap: () => _openCategory(ChatHistoryCategoryKind.media),
                ),
                const SizedBox(height: 12),
                _CategoryTile(
                  icon: Icons.insert_drive_file_outlined,
                  label: '文件',
                  onTap: () => _openCategory(ChatHistoryCategoryKind.files),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
