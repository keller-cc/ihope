import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import 'chat_history_date_tab.dart';
import 'chat_history_files_tab.dart';
import 'chat_history_jump.dart';
import 'chat_history_loader.dart';
import 'chat_history_media_tab.dart';
import 'chat_history_members_tab.dart';

enum ChatHistoryCategoryKind { date, members, media, files }

/// 日期 / 群成员 / 图片视频 / 文件 独立页。
class ChatHistoryCategoryScreen extends StatefulWidget {
  const ChatHistoryCategoryScreen({
    super.key,
    required this.kind,
    required this.auth,
    required this.conversation,
    required this.loader,
  });

  final ChatHistoryCategoryKind kind;
  final AuthService auth;
  final ConversationItem conversation;
  final ChatHistoryLoader loader;

  @override
  State<ChatHistoryCategoryScreen> createState() =>
      _ChatHistoryCategoryScreenState();
}

class _ChatHistoryCategoryScreenState extends State<ChatHistoryCategoryScreen> {
  List<ChatMessage> _messages = [];
  bool _loading = true;
  late final Future<List<ChatMessage>> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.loader.load();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final msgs = await _loadFuture;
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
  }

  Future<List<ChatMessage>> _ensureMessages() async {
    if (!_loading) return _messages;
    return _loadFuture;
  }

  void _jumpToMessage(String? messageId) {
    Navigator.of(context).pop(ChatHistoryJump(messageId: messageId));
  }

  String get _title => switch (widget.kind) {
        ChatHistoryCategoryKind.date => '按日期查找',
        ChatHistoryCategoryKind.members => '群成员',
        ChatHistoryCategoryKind.media => '图片/视频',
        ChatHistoryCategoryKind.files => '文件',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (widget.kind) {
      case ChatHistoryCategoryKind.date:
        return ChatHistoryDateTab(
          messages: _messages,
          loadMessages: _ensureMessages,
          onPick: (id) => _jumpToMessage(id),
          onEmpty: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('该日期之后暂无消息')),
            );
          },
        );
      case ChatHistoryCategoryKind.members:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return ChatHistoryMembersTab(
          auth: widget.auth,
          conversation: widget.conversation,
          messages: _messages,
          onJump: _jumpToMessage,
        );
      case ChatHistoryCategoryKind.media:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return ChatHistoryMediaTab(
          auth: widget.auth,
          conversation: widget.conversation,
          messages: _messages,
        );
      case ChatHistoryCategoryKind.files:
        if (_loading) return const Center(child: CircularProgressIndicator());
        return ChatHistoryFilesTab(
          auth: widget.auth,
          conversation: widget.conversation,
          messages: _messages,
        );
    }
  }
}
