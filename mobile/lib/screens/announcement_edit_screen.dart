import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../utils/announcement_payload.dart';
import '../widgets/standard_emoji_panel.dart';

/// 发布 / 编辑群公告（标题 + 正文 + 标准表情）。
class AnnouncementEditScreen extends StatefulWidget {
  const AnnouncementEditScreen({
    super.key,
    required this.auth,
    required this.conversation,
    this.initial,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final AnnouncementPayload? initial;

  @override
  State<AnnouncementEditScreen> createState() => _AnnouncementEditScreenState();
}

class _AnnouncementEditScreenState extends State<AnnouncementEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final FocusNode _bodyFocus;
  bool _emojiOpen = false;
  bool _saving = false;

  static const _titleMax = 40;
  static const _bodyMax = 2000;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _body = TextEditingController(text: widget.initial?.body ?? '');
    _bodyFocus = FocusNode();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final payload = AnnouncementPayload(
      title: _title.text.trim(),
      body: _body.text.trim(),
    );
    if (payload.body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写公告正文')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final sent = await widget.auth.sendChatMessage(
        widget.conversation,
        payload.encode(),
        type: 'announcement',
      );
      if (!mounted) return;
      Navigator.pop(context, sent);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑群公告' : '发布群公告'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _publish,
              child: const Text('发布'),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '公告与群消息同样加密；新入群成员看不到入群前的历史公告。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _title,
                  maxLength: _titleMax,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '标题',
                    hintText: '例如：本周聚会通知',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _bodyFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _body,
                  focusNode: _bodyFocus,
                  maxLines: 12,
                  maxLength: _bodyMax,
                  decoration: InputDecoration(
                    labelText: '正文',
                    hintText: '请输入公告详细内容',
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                    suffixIcon: IconButton(
                      tooltip: _emojiOpen ? '收起表情' : '插入表情',
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        color: _emojiOpen
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () {
                        setState(() => _emojiOpen = !_emojiOpen);
                        if (!_emojiOpen) {
                          _bodyFocus.requestFocus();
                        } else {
                          _bodyFocus.unfocus();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_emojiOpen)
            StandardEmojiPanel(
              height: 260,
              controller: _body,
            ),
        ],
      ),
    );
  }
}
