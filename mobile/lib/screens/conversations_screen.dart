import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../utils/conversation_sort.dart';
import '../widgets/realtime_indicator.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'new_group_screen.dart';
import 'profile_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    super.key,
    required this.auth,
    required this.onLogout,
  });

  final AuthService auth;
  final Future<void> Function() onLogout;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<ConversationItem> _items = [];
  List<String> _pinnedIds = [];
  final Map<String, String> _previews = {};
  bool _loading = true;
  String? _error;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<GroupDissolvedFrame>? _dissolvedSub;
  StreamSubscription<ConversationAddedFrame>? _addedSub;
  StreamSubscription<ConversationRemovedFrame>? _removedSub;
  StreamSubscription<ConversationUpdatedFrame>? _updatedSub;

  @override
  void initState() {
    super.initState();
    _load();
    _msgSub = widget.auth.ws.onMessage.listen(_onIncomingMessage);
    _connSub = widget.auth.ws.onConnectionChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _dissolvedSub = widget.auth.ws.onGroupDissolved.listen(_onGroupDissolved);
    _addedSub = widget.auth.ws.onConversationAdded.listen(_onConversationAdded);
    _removedSub =
        widget.auth.ws.onConversationRemoved.listen(_onConversationRemoved);
    _updatedSub =
        widget.auth.ws.onConversationUpdated.listen(_onConversationUpdated);
  }

  void _onConversationUpdated(ConversationUpdatedFrame frame) {
    if (!mounted) return;
    final conv = ConversationItem.fromJson(frame.conversation);
    final idx = _items.indexWhere((c) => c.id == conv.id);
    if (idx < 0) return;
    final wasArchived = _items[idx].isArchived;
    setState(() {
      _items[idx] = widget.auth.mergeConversationUpdate(_items[idx], conv);
      _items = sortConversationsByPin(_items, _pinnedIds);
    });
    if (wasArchived) {
      unawaited(widget.auth.reactivateConversation(_items[idx]));
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _dissolvedSub?.cancel();
    _addedSub?.cancel();
    _removedSub?.cancel();
    _updatedSub?.cancel();
    super.dispose();
  }

  Future<void> _onConversationAdded(ConversationAddedFrame frame) async {
    if (!mounted) return;
    final conv =
        await widget.auth.reactivateConversation(
      ConversationItem.fromJson(frame.conversation),
    );
    final me = widget.auth.currentUser!;
    final title = conv.displayTitle(me.id);

    await widget.auth.ensureGroupKeys(conv);

    final existing = _items.indexWhere((c) => c.id == conv.id);
    if (existing >= 0) {
      if (!mounted) return;
      setState(() {
        _items[existing] = conv;
        _items = sortConversationsByPin(_items, _pinnedIds);
      });
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('你已加入群聊「$title」')),
    );
    var preview = '暂无消息';
    if (conv.lastMessage != null) {
      preview = await widget.auth.decryptPreview(conv, conv.lastMessage!);
    }
    if (!mounted) return;
    setState(() {
      if (conv.lastMessage != null) {
        _previews[conv.id] = preview;
      }
      _items = sortConversationsByPin([conv, ..._items], _pinnedIds);
    });
  }

  Future<void> _onConversationRemoved(ConversationRemovedFrame frame) async {
    if (!mounted) return;

    ConversationItem? conv;
    for (final c in _items) {
      if (c.id == frame.conversationId) {
        conv = c;
        break;
      }
    }
    final title = conv?.displayTitle(widget.auth.currentUser!.id) ?? '群聊';

    await widget.auth.handleConversationRemoved(
      frame.conversationId,
      snapshot: conv,
    );
    if (!mounted) return;

    _pinnedIds = await widget.auth.pinnedConversationIds();
    setState(() {
      final index = _items.indexWhere((c) => c.id == frame.conversationId);
      if (index >= 0) {
        _items[index] = _items[index].copyWith(isArchived: true);
      }
      _items = sortConversationsByPin(_items, _pinnedIds);
    });

    if (!widget.auth.claimRemovalUi(frame.conversationId)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('你已被移出群聊「$title」，可在本地查看历史消息')),
    );
  }

  Future<void> _onGroupDissolved(GroupDissolvedFrame frame) async {
    if (!mounted) return;

    final me = widget.auth.currentUser!;
    final isSelf = frame.dissolvedBy == me.id;

    ConversationItem? conv;
    for (final c in _items) {
      if (c.id == frame.conversationId) {
        conv = c;
        break;
      }
    }

    await widget.auth.handleGroupDissolved(frame.conversationId);

    if (!isSelf) {
      final name =
          frame.groupName.isNotEmpty ? frame.groupName : '群聊';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('群聊已解散'),
          content: Text('群聊「$name」已被解散，可在本地查看历史消息'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }

    if (!mounted) return;
    _pinnedIds = await widget.auth.pinnedConversationIds();
    setState(() {
      final index = _items.indexWhere((c) => c.id == frame.conversationId);
      if (index >= 0) {
        _items[index] = _items[index].copyWith(isArchived: true);
      } else if (conv != null) {
        _items = [conv.copyWith(isArchived: true), ..._items];
      }
      _items = sortConversationsByPin(_items, _pinnedIds);
    });
  }

  void _onIncomingMessage(ChatMessage msg) {
    if (!mounted) return;

    final index = _items.indexWhere((c) => c.id == msg.conversationId);
    if (index < 0) {
      _load();
      return;
    }

    final conv = _items[index];
    final me = widget.auth.currentUser!;
    if (conv.type == 'group' &&
        msg.type != 'system' &&
        msg.epoch < conv.joinedEpochFor(me.id)) {
      return;
    }

    unawaited(_applyIncomingPreview(conv, msg));
  }

  Future<void> _applyIncomingPreview(
    ConversationItem conv,
    ChatMessage msg,
  ) async {
    final preview = await widget.auth.decryptPreview(conv, msg);
    if (!mounted) return;
    final updated = conv.copyWith(lastMessage: msg);
    setState(() {
      _previews[conv.id] = preview;
      final others = _items.where((c) => c.id != conv.id).toList();
      _items = sortConversationsByPin([updated, ...others], _pinnedIds);
    });
  }

  Future<void> _refreshPinOrder() async {
    _pinnedIds = await widget.auth.pinnedConversationIds();
    if (!mounted) return;
    setState(() {
      _items = sortConversationsByPin(_items, _pinnedIds);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.reconnectRealtime();
      final pinned = await widget.auth.pinnedConversationIds();
      final items = await widget.auth.listAllConversations();
      final sorted = sortConversationsByPin(items, pinned);
      final previews = <String, String>{};
      for (final item in items) {
        final last = item.lastMessage;
        if (last != null) {
          previews[item.id] =
              await widget.auth.decryptPreview(item, last);
        }
      }
      if (!mounted) return;
      setState(() {
        _pinnedIds = pinned;
        _items = sorted;
        _previews
          ..clear()
        ..addAll(previews);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat(ConversationItem conv) async {
    var item = conv;
    if (conv.isArchived) {
      final reactivated = await widget.auth.tryReactivateConversation(conv);
      if (reactivated != null) item = reactivated;
    }
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ChatScreen(auth: widget.auth, conversation: item),
      ),
    );
    if (!mounted) return;
    final refreshed = await widget.auth.tryReactivateConversation(item);
    if (refreshed != null) {
      setState(() {
        final index = _items.indexWhere((c) => c.id == conv.id);
        if (index >= 0) {
          _items[index] = refreshed;
        }
      });
    }
    if (result == 'left') {
      setState(() {
        final index = _items.indexWhere((c) => c.id == conv.id);
        if (index >= 0) {
          _items[index] = _items[index].copyWith(isArchived: true);
        }
      });
      return;
    }
    if (result == 'dissolved') {
      setState(() {
        final index = _items.indexWhere((c) => c.id == conv.id);
        if (index >= 0) {
          _items[index] = _items[index].copyWith(isArchived: true);
        }
      });
      return;
    }
    await _refreshPinOrder();
  }

  Future<void> _openProfile() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          auth: widget.auth,
          onProfileUpdated: () => setState(() {}),
        ),
      ),
    );
    if (result == 'logout' && mounted) {
      await widget.onLogout();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openNewChat() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('发起单聊'),
              onTap: () => Navigator.pop(ctx, 'private'),
            ),
            ListTile(
              leading: const Icon(Icons.groups),
              title: const Text('创建群聊'),
              onTap: () => Navigator.pop(ctx, 'group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    final conv = await Navigator.of(context).push<ConversationItem>(
      MaterialPageRoute(
        builder: (_) => choice == 'group'
            ? NewGroupScreen(auth: widget.auth)
            : NewChatScreen(auth: widget.auth),
      ),
    );
    if (conv != null && mounted) {
      setState(() {
        if (!_items.any((c) => c.id == conv.id)) {
          _items = [conv, ..._items];
        }
      });
      if (!mounted) return;
      await _openChat(conv);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser!;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(
              name: me.username,
              imageUrl: me.avatarUrl,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '你好，${me.username}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          RealtimeIndicator(
            connected: widget.auth.ws.isConnected,
            onReconnect: widget.auth.ws.isConnected
                ? null
                : () => widget.auth.reconnectRealtime(),
          ),
          IconButton(
            tooltip: '个人资料',
            onPressed: _openProfile,
            icon: const Icon(Icons.person),
          ),
          IconButton(
            tooltip: '退出',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewChat,
        child: const Icon(Icons.chat),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!),
                      ),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text('暂无会话，点右下角发起聊天')),
                        ],
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final preview = item.lastMessage == null
                              ? '暂无消息'
                              : (_previews[item.id] ??
                                  item.lastMessage!.displayText);
                          final peerName = item.displayTitle(me.id);
                          final isPinned = _pinnedIds.contains(item.id);
                          return ListTile(
                            leading: UserAvatar(
                              name: peerName,
                              imageUrl: item.displayAvatarUrl(me.id),
                            ),
                            title: Row(
                              children: [
                                if (isPinned)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    peerName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              item.isArchived
                                  ? '已退出 · $preview'
                                  : item.type == 'group'
                                      ? '${item.members.length} 人 · $preview'
                                      : preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _openChat(item),
                          );
                        },
                      ),
      ),
    );
  }
}
