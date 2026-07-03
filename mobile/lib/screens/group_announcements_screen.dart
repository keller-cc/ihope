import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../utils/announcement_payload.dart';
import '../utils/announcement_read.dart';
import '../widgets/app_page_route.dart';
import '../widgets/announcement_card.dart';
import 'announcement_detail_screen.dart';
import 'announcement_edit_screen.dart';

/// 群公告历史列表（独立界面）。
class GroupAnnouncementsScreen extends StatefulWidget {
  const GroupAnnouncementsScreen({
    super.key,
    required this.auth,
    required this.conversation,
    this.initialAnnouncements,
  });

  final AuthService auth;
  final ConversationItem conversation;
  /// 从聊天页带入已解密的公告，可立即展示。
  final List<ChatMessage>? initialAnnouncements;

  @override
  State<GroupAnnouncementsScreen> createState() =>
      _GroupAnnouncementsScreenState();
}

class _GroupAnnouncementsScreenState extends State<GroupAnnouncementsScreen> {
  List<ChatMessage> _announcements = [];
  Set<String> _readAnnouncementIds = {};
  bool _loading = true;
  bool _syncingRemote = false;
  String? _error;

  bool get _canManage {
    final me = widget.auth.currentUser;
    return me != null && widget.conversation.canManageGroup(me.id);
  }

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
      final phase1 = await widget.auth.loadAnnouncementsFromCache(
        widget.conversation,
        seed: widget.initialAnnouncements,
      );
      if (!mounted) return;
      setState(() {
        _announcements = phase1.announcements;
        _readAnnouncementIds = phase1.readIds;
        _loading = false;
      });
      if (!widget.conversation.isArchived) {
        unawaited(_syncRemote());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _syncRemote() async {
    if (_syncingRemote) return;
    _syncingRemote = true;
    try {
      final refreshed = await widget.auth.refreshAnnouncementsRemote(
        widget.conversation,
        _announcements,
      );
      if (!mounted) return;
      setState(() => _announcements = refreshed);
    } finally {
      _syncingRemote = false;
    }
  }

  bool _isUnread(ChatMessage ann) {
    final me = widget.auth.currentUser!;
    return AnnouncementRead.isItemUnread(
      announcement: ann,
      readIds: _readAnnouncementIds,
      myUserId: me.id,
    );
  }

  Future<void> _markAnnouncementReadFor(ChatMessage ann) async {
    await widget.auth.markAnnouncementRead(widget.conversation.id, ann.id);
    if (!mounted) return;
    setState(() => _readAnnouncementIds = {..._readAnnouncementIds, ann.id});
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
      appPageRoute(
        builder: (_) => AnnouncementEditScreen(
          auth: widget.auth,
          conversation: widget.conversation,
        ),
      ),
    );
    if (sent == null || !mounted) return;
    setState(() {
      _announcements = AnnouncementRead.allOf([..._announcements, sent]);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('群公告已发布')),
    );
  }

  Future<void> _editAnnouncement(ChatMessage ann) async {
    if (!_canManage) return;
    final payload = AnnouncementPayload.fromMessage(ann);
    final sent = await Navigator.of(context).push<ChatMessage>(
      appPageRoute(
        builder: (_) => AnnouncementEditScreen(
          auth: widget.auth,
          conversation: widget.conversation,
          initial: payload,
        ),
      ),
    );
    if (sent == null || !mounted) return;
    setState(() {
      _announcements = AnnouncementRead.allOf([..._announcements, sent]);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('群公告已发布')),
    );
  }

  void _showAnnouncementActions(ChatMessage ann) {
    if (!_canManage) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑并重新发布'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_editAnnouncement(ann));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = widget.auth.currentUser;
    final unreadCount = me == null
        ? 0
        : AnnouncementRead.countUnread(
            _announcements,
            readIds: _readAnnouncementIds,
            myUserId: me.id,
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('群公告'),
        actions: [
          if (_syncingRemote)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
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
      floatingActionButton: _canManage && !widget.conversation.isArchived
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
                  onRefresh: () async {
                    await _load();
                    await _syncRemote();
                  },
                  child: _announcements.isEmpty
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
                                    if (_canManage) ...[
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
                          itemCount: _announcements.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final ann = _announcements[index];
                            return GestureDetector(
                              onLongPress: _canManage
                                  ? () => _showAnnouncementActions(ann)
                                  : null,
                              child: AnnouncementCard(
                                msg: ann,
                                isUnread: _isUnread(ann),
                                onTap: () => unawaited(_openDetail(ann)),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
