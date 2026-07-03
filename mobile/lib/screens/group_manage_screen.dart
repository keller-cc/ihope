import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../utils/announcement_read.dart';
import '../utils/avatar_picker.dart';
import '../widgets/app_page_route.dart';
import '../widgets/conversation_common_settings.dart';
import '../widgets/member_title_badge.dart';
import '../widgets/user_avatar.dart';
import 'announcement_edit_screen.dart';
import 'group_announcements_screen.dart';

/// 群聊管理：成员列表、邀请、踢人、退群、解散。
class GroupManageScreen extends StatefulWidget {
  const GroupManageScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<GroupManageScreen> createState() => _GroupManageScreenState();
}

class _GroupManageScreenState extends State<GroupManageScreen> {
  late ConversationItem _conversation;
  bool _busy = false;
  bool _uploadingAvatar = false;
  bool _pinned = false;
  bool _announcementUnread = false;
  ChatMessage? _latestAnnouncement;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _reload();
    _loadPinState();
    unawaited(_loadAnnouncementState());
  }

  Future<void> _loadAnnouncementState() async {
    final cached = await widget.auth.loadCachedMessages(_conversation.id);
    final latest = AnnouncementRead.latestOf(cached);
    final readIds = await widget.auth.announcementReadIdsFor(_conversation.id);
    final me = widget.auth.currentUser;
    if (!mounted || me == null) return;
    setState(() {
      _latestAnnouncement = latest;
      _announcementUnread = AnnouncementRead.isUnread(
        announcement: latest,
        readIds: readIds,
        myUserId: me.id,
        allMessages: cached,
      );
    });
  }

  Future<void> _loadPinState() async {
    final pinned =
        await widget.auth.isConversationPinned(_conversation.id);
    if (mounted) setState(() => _pinned = pinned);
  }

  Future<void> _togglePin(bool value) async {
    await widget.auth.setConversationPinned(
      _conversation.id,
      pinned: value,
    );
    if (!mounted) return;
    setState(() => _pinned = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? '已置顶' : '已取消置顶')),
    );
  }

  Future<void> _reload() async {
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (mounted) setState(() => _conversation = fresh);
  }

  bool get _isOwner {
    final me = widget.auth.currentUser!;
    return _conversation.isOwner(me.id);
  }

  bool get _canManage {
    final me = widget.auth.currentUser!;
    return _conversation.canManageGroup(me.id);
  }

  bool _canRemoveMember(ConversationMember member) {
    final me = widget.auth.currentUser!;
    if (member.userId == me.id) return true;
    if (_conversation.isOwner(member.userId)) return false;
    if (_isOwner) return true;
    if (_canManage && !member.isAdmin) return true;
    return false;
  }

  Future<void> _toggleAdmin(ConversationMember member) async {
    final me = widget.auth.currentUser!;
    if (!_isOwner ||
        member.userId == me.id ||
        _conversation.isOwner(member.userId)) {
      return;
    }
    final makeAdmin = !member.isAdmin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(makeAdmin ? '设为管理员' : '取消管理员'),
        content: Text(makeAdmin
            ? '确定将 ${member.username} 设为管理员？管理员可邀请成员、移除普通成员、发布群公告。'
            : '确定取消 ${member.username} 的管理员身份？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final updated = await widget.auth.setGroupMemberRole(
        _conversation,
        member.userId,
        makeAdmin ? 'admin' : 'member',
      );
      if (!mounted) return;
      setState(() => _conversation = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMemberMenu(ConversationMember member) {
    final me = widget.auth.currentUser!;
    if (!_isOwner ||
        member.userId == me.id ||
        _conversation.isOwner(member.userId)) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                member.isAdmin
                    ? Icons.admin_panel_settings_outlined
                    : Icons.admin_panel_settings,
              ),
              title: Text(member.isAdmin ? '取消管理员' : '设为管理员'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_toggleAdmin(member));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('移除成员'),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_removeMember(member));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAnnouncements() async {
    await Navigator.of(context).push<void>(
      appPageRoute(
        builder: (_) => GroupAnnouncementsScreen(
          auth: widget.auth,
          conversation: _conversation,
        ),
      ),
    );
    if (!mounted) return;
    await _loadAnnouncementState();
  }

  Future<void> _publishAnnouncement() async {
    final sent = await Navigator.of(context).push<ChatMessage>(
      appPageRoute(
        builder: (_) => AnnouncementEditScreen(
          auth: widget.auth,
          conversation: _conversation,
        ),
      ),
    );
    if (sent != null) await _loadAnnouncementState();
  }

  Future<void> _renameGroup() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameGroupDialog(
        initialName: _conversation.name ?? '',
      ),
    );
    if (newName == null || newName.isEmpty) return;
    if (newName == _conversation.name) return;

    setState(() => _busy = true);
    try {
      final updated =
          await widget.auth.updateGroupName(_conversation, newName);
      if (!mounted) return;
      setState(() => _conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('群名称已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickGroupAvatar() async {
    final cropped = await pickAndCropAvatar(context);
    if (cropped == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final updated = await widget.auth.uploadGroupAvatar(
        _conversation,
        cropped,
        filename: 'avatar.jpg',
      );
      if (!mounted) return;
      setState(() => _conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('群头像已更新')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }
  Future<void> _inviteMembers() async {
    final me = widget.auth.currentUser!.id;
    final existing = _conversation.members.map((m) => m.userId).toSet();
    existing.add(me);

    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, scrollController) => _InviteMembersSheet(
          auth: widget.auth,
          excludeIds: existing,
          scrollController: scrollController,
        ),
      ),
    );

    if (selected == null || selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.auth.addGroupMembers(
        _conversation,
        selected.toList(),
      );
      if (!mounted) return;
      setState(() => _conversation = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已邀请成员')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember(ConversationMember member) async {
    final me = widget.auth.currentUser!;
    final isSelf = member.userId == me.id;
    if (!_canRemoveMember(member)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isSelf ? '退出群聊' : '移除成员'),
        content: Text(isSelf
            ? '确定退出「${_conversation.name}」吗？'
            : '确定将 ${member.username} 移出群聊吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSelf ? '退出' : '移除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      if (isSelf && !_isOwner) {
        await widget.auth.leaveGroup(_conversation);
        if (!mounted) return;
        Navigator.of(context).pop('left');
        return;
      }
      final updated =
          await widget.auth.removeGroupMember(_conversation, member.userId);
      if (!mounted) return;
      setState(() => _conversation = updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dissolveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散群聊'),
        content: Text('确定解散「${_conversation.name}」？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解散'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await widget.auth.dissolveGroup(_conversation);
      if (!mounted) return;
      Navigator.of(context).pop('dissolved');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_conversation.name ?? '群聊'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _isOwner && !_busy && !_uploadingAvatar
                      ? _pickGroupAvatar
                      : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatar(
                        name: _conversation.name ?? '群聊',
                        imageUrl: _conversation.avatarUrl,
                        radius: 40,
                      ),
                      if (_uploadingAvatar)
                        const SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (_isOwner && !_uploadingAvatar)
                        CircleAvatar(                          radius: 14,
                          child: Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _conversation.name ?? '群聊',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_isOwner)
                  TextButton.icon(
                    onPressed: _busy ? null : _renameGroup,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('修改群名称'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConversationCommonSettings(
            auth: widget.auth,
            conversation: _conversation,
            pinned: _pinned,
            enabled: !_busy,
            onPinChanged: (v) => unawaited(_togglePin(v)),
          ),
          if (_canManage)
            ListTile(
              leading: Badge(
                isLabelVisible: _announcementUnread,
                backgroundColor: Theme.of(context).colorScheme.error,
                smallSize: 8,
                child: const Icon(Icons.campaign_outlined),
              ),
              title: const Text('群公告'),
              subtitle: Text(
                _latestAnnouncement == null
                    ? '发布群公告（新成员看不到入群前的公告）'
                    : _announcementUnread
                        ? '有新公告未读 · 查看全部历史'
                        : '查看全部历史公告或发布新公告',
              ),
              onTap: _busy ? null : () => unawaited(_openAnnouncements()),
              trailing: TextButton(
                onPressed: _busy ? null : () => unawaited(_publishAnnouncement()),
                child: const Text('发布'),
              ),
            ),
          if (!_canManage)
            ListTile(
              leading: Badge(
                isLabelVisible: _announcementUnread,
                backgroundColor: Theme.of(context).colorScheme.error,
                smallSize: 8,
                child: const Icon(Icons.campaign_outlined),
              ),
              title: const Text('群公告'),
              subtitle: Text(
                _announcementUnread ? '有新公告未读' : '查看全部历史群公告',
              ),
              onTap: _busy ? null : () => unawaited(_openAnnouncements()),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.group),
            title: Text('${_conversation.members.length} 位成员'),
            subtitle: Text('Epoch ${_conversation.epoch}'),
          ),
          const Divider(height: 1),
          ..._conversation.members.map((m) {
            final title = _conversation.memberTitle(m.userId);
            final canRemove = _canRemoveMember(m) && m.userId != me.id;
            final canLeave = m.userId == me.id && !_isOwner;
            return ListTile(
              leading: UserAvatar(
                name: m.username,
                imageUrl: m.avatarUrl,
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      m.username,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (title != null) MemberTitleBadge(title: title),
                ],
              ),
              subtitle: m.userId == me.id ? const Text('我') : null,
              onLongPress: _isOwner &&
                      m.userId != me.id &&
                      !_conversation.isOwner(m.userId)
                  ? () => _showMemberMenu(m)
                  : null,
              trailing: canRemove || canLeave
                  ? IconButton(
                      icon: Icon(canLeave ? Icons.logout : Icons.person_remove),
                      tooltip: canLeave ? '退出群聊' : '移除成员',
                      onPressed: _busy ? null : () => _removeMember(m),
                    )
                  : null,
            );
          }),
          const SizedBox(height: 16),
          if (_canManage)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: _busy ? null : _inviteMembers,
                icon: const Icon(Icons.person_add),
                label: const Text('邀请成员'),
              ),
            ),
          if (!_isOwner)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _removeMember(
                          _conversation.members
                              .firstWhere((m) => m.userId == me.id),
                        ),
                icon: const Icon(Icons.logout),
                label: const Text('退出群聊'),
              ),
            ),
          if (_isOwner) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _dissolveGroup,
                icon: const Icon(Icons.delete_forever),
                label: const Text('解散群聊'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InviteMembersSheet extends StatefulWidget {
  const _InviteMembersSheet({
    required this.auth,
    required this.excludeIds,
    required this.scrollController,
  });

  final AuthService auth;
  final Set<String> excludeIds;
  final ScrollController scrollController;

  @override
  State<_InviteMembersSheet> createState() => _InviteMembersSheetState();
}

class _InviteMembersSheetState extends State<_InviteMembersSheet> {
  final _search = TextEditingController();
  final _picked = <String>{};
  List<PublicUser> _users = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadUsers([String? query]) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.auth.conversations.listUsers(
        query: (query == null || query.trim().isEmpty) ? null : query.trim(),
      );
      if (!mounted) return;
      setState(() {
        _users =
            users.where((u) => !widget.excludeIds.contains(u.id)).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadUsers(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('邀请成员', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: '搜索用户名',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: _loadUsers,
            ),
            if (_picked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('已选 ${_picked.length} 人'),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : _users.isEmpty
                          ? const Center(child: Text('没有可邀请的用户'))
                          : ListView.separated(
                              controller: widget.scrollController,
                              itemCount: _users.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final u = _users[index];
                                return CheckboxListTile(
                                  secondary: UserAvatar(
                                    name: u.username,
                                    imageUrl: u.avatarUrl,
                                  ),
                                  title: Text(u.username),
                                  value: _picked.contains(u.id),
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _picked.add(u.id);
                                      } else {
                                        _picked.remove(u.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton(
                onPressed:
                    _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
                child: Text('邀请 ${_picked.length} 人'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameGroupDialog extends StatefulWidget {
  const _RenameGroupDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameGroupDialog> createState() => _RenameGroupDialogState();
}

class _RenameGroupDialogState extends State<_RenameGroupDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改群名称'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          hintText: '群名称',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
