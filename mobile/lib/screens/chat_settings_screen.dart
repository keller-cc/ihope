import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../widgets/conversation_common_settings.dart';

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

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    final title = widget.conversation.displayTitle(me.id);
    return Scaffold(
      appBar: AppBar(title: Text('$title · 设置')),
      body: ListView(
        children: [
          ConversationCommonSettings(
            auth: widget.auth,
            conversation: widget.conversation,
            pinned: _pinned,
            onPinChanged: (v) => unawaited(_togglePin(v)),
          ),
        ],
      ),
    );
  }
}
