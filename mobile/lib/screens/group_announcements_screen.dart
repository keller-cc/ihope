import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../utils/announcement_read.dart';
import '../widgets/announcement_card.dart';
import 'announcement_detail_screen.dart';
import 'announcement_edit_screen.dart';

/// 群公告历史列表（独立界面）。
class GroupAnnouncementsScreen extends StatefulWidget {
  const GroupAnnouncementsScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<GroupAnnouncementsScreen> createState() =>
      _GroupAnnouncementsScreenState();
}

class _GroupAnnouncementsScreenState extends State<GroupAnnouncementsScreen> {
  List<ChatMessage> _messages = [];
  String? _readMessageId;
  bool _loading = true;
  String? _error;

  bool get _isOwner {
    final me = widget.auth.currentUser;
    return me != null && widget.conversation.isOwner(me.id);
  }

  List<ChatMessage> get _announcements => AnnouncementRead.allOf(_messages);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final readId =
          await widget.auth.announcementReadIdFor(widget.conversation.id);
      var cached = await widget.auth.loadCachedMessages(widget.conversation.id);
      cached = await widget.auth.decryptMessagesLocal(
        widget.conversation,
        cached,
      );
      if (!widget.conversation.isArchived) {
        try {
          final remote = await widget.auth.conversations.listMessages(
            widget.conversation.id,
            limit: 100,
          );
          cached = _merge(remote, cached);
          cached = await widget.auth.decryptMessagesLocal(
            widget.conversation,
            cached,
          );
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _messages = cached;
        _readMessageId = readId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<ChatMessage> _merge(List<ChatMessage> remote, List<ChatMessage> cached) {
    final byId = {for (final m in remote) m.id: m};
    for (final c in cached) {
      final r = byId[c.id];
      if (r == null) {
        byId[c.id] = c;
      } else if (c.plaintext != null && c.plaintext!.isNotEmpty) {
        byId[c.id] = r.copyWith(plaintext: c.plaintext);
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  bool _isUnread(ChatMessage ann) {
    final me = widget.auth.currentUser!;
    return AnnouncementRead.isItemUnread(
      announcement: ann,
      readMarker: AnnouncementRead.findById(_messages, _readMessageId),
      myUserId: me.id,
    );
  }

  Future<void> _markAnnouncementReadFor(ChatMessage ann) async {
    await widget.auth.markAnnouncementRead(widget.conversation.id, ann.id);
    if (!mounted) return;
    setState(() => _readMessageId = ann.id);
  }

  Future<void> _openDetail(ChatMessage ann) async {
    final name =
        widget.auth.groupMemberUsername(widget.conversation, ann.senderId);
    await AnnouncementDetailScreen.open(
      context,
      msg: ann,
      publisherName: name,
      onMarkRead: () => unawaited(_markAnnouncementReadFor(ann)),
    );
  }

  Future<void> _publish() async {
    final sent = await Navigator.of(context).push<ChatMessage>(
      MaterialPageRoute(
        builder: (_) => AnnouncementEditScreen(
          auth: widget.auth,
          conversation: widget.conversation,
        ),
      ),
    );
    if (sent == null || !mounted) return;
    setState(() {
      _messages = [..._messages, sent];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('群公告已发布')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final announcements = _announcements;
    final me = widget.auth.currentUser;
    final unreadCount = me == null
        ? 0
        : AnnouncementRead.countUnread(
            _messages,
            readMessageId: _readMessageId,
            myUserId: me.id,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('群公告'),
        actions: [
          if (unreadCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  label: Text('$unreadCount 条未读'),
                  backgroundColor: scheme.errorContainer,
                  labelStyle: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isOwner && !widget.conversation.isArchived
          ? FloatingActionButton.extended(
              onPressed: _publish,
              icon: const Icon(Icons.add),
              label: const Text('发布公告'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: announcements.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.campaign_outlined,
                                      size: 56,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '暂无群公告',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (_isOwner) ...[
                                      const SizedBox(height: 8),
                                      const Text('点击右下角发布第一条公告'),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          itemCount: announcements.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final ann = announcements[index];
                            final unread = _isUnread(ann);
                            return AnnouncementCard(
                              msg: ann,
                              isUnread: unread,
                              onTap: () => unawaited(_openDetail(ann)),
                            );
                          },
                        ),
                ),
    );
  }
}
