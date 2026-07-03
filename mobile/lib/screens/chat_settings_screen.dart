import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import 'chat_history/chat_history_hub_screen.dart';
import 'chat_history/chat_history_jump.dart';

/// 单聊设置：置顶、搜索等。
class ChatSettingsScreen extends StatefulWidget {
  const ChatSettingsScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPinState());
  }

  Future<void> _loadPinState() async {
    final pinned =
        await widget.auth.isConversationPinned(widget.conversation.id);
    if (mounted) setState(() => _pinned = pinned);
  }

  Future<void> _togglePin(bool value) async {
    await widget.auth.setConversationPinned(
      widget.conversation.id,
      pinned: value,
    );
    if (!mounted) return;
    setState(() => _pinned = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? '已置顶' : '已取消置顶')),
    );
  }

  Future<void> _openSearch() async {
    final jump = await Navigator.of(context).push<ChatHistoryJump>(
      MaterialPageRoute(
        builder: (_) => ChatHistoryHubScreen(
          auth: widget.auth,
          conversation: widget.conversation,
        ),
      ),
    );
    if (jump != null && mounted) {
      Navigator.of(context).pop(jump);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    final title = widget.conversation.displayTitle(me.id);
    return Scaffold(
      appBar: AppBar(title: Text('$title · 设置')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: const Text('置顶会话'),
            subtitle: const Text('置顶后在首页列表靠前显示'),
            value: _pinned,
            onChanged: (v) => unawaited(_togglePin(v)),
          ),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('查找聊天记录'),
            subtitle: const Text('按日期、成员、图片与文件查找'),
            onTap: _openSearch,
          ),
        ],
      ),
    );
  }
}
