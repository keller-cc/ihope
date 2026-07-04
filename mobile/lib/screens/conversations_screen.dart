import 'dart:async';

import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/ws_service.dart';
import '../utils/announcement_payload.dart';
import '../utils/conversation_sort.dart';
import '../utils/media_payload.dart';
import '../utils/message_time.dart';
import '../widgets/home_connection_status.dart';
import '../widgets/offline_banner.dart';
import '../widgets/swipe_action_tile.dart';
import '../widgets/user_avatar.dart';
import '../widgets/app_page_route.dart';
import '../widgets/slide_from_left_route.dart';
import 'account_panel_screen.dart';
import 'chat/chat_thread_loader.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';
import 'new_group_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'home_search/home_search_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    super.key,
    required this.auth,
    required this.onLogout,
    required this.notification,
    this.pendingPushConversation,
  });

  final AuthService auth;
  final NotificationService notification;
  final Future<void> Function() onLogout;
  final ValueNotifier<String?>? pendingPushConversation;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen>
    with WidgetsBindingObserver {
  List<ConversationItem> _items = [];
  List<String> _pinnedIds = [];
  final Map<String, String> _previews = {};
  final Map<String, List<ChatMessage>> _messageCache = {};
  final Map<String, int> _unreadCounts = {};
  final Map<String, bool> _announcementUnread = {};
  Set<String> _hiddenIds = {};
  bool _refreshing = false;
  String? _error;
  String? _offlineNotice;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<GroupDissolvedFrame>? _dissolvedSub;
  StreamSubscription<ConversationAddedFrame>? _addedSub;
  StreamSubscription<ConversationRemovedFrame>? _removedSub;
  StreamSubscription<ConversationUpdatedFrame>? _updatedSub;
  StreamSubscription<ConversationItem>? _patchedSub;
  StreamSubscription<void>? _realtimeRestoredSub;
  StreamSubscription<String>? _groupKeySub;
  bool _syncAfterOnlineInFlight = false;
  bool _loadInFlight = false;
  bool _resumeRefreshInFlight = false;

  void _syncOfflineNotice() {
    _offlineNotice = widget.auth.ws.isConnected
        ? null
        : '推送未连接，新消息需手动刷新';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    widget.pendingPushConversation?.addListener(_onPendingPushConversation);
    unawaited(widget.auth.ensureRealtimeConnected());
    _msgSub = widget.auth.ws.onMessage.listen(_onIncomingMessage);
    _connSub = widget.auth.ws.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(_syncOfflineNotice);
      if (connected) unawaited(_syncAfterOnline());
    });
    _realtimeRestoredSub =
        widget.auth.onRealtimeRestored.listen((_) {
      if (!mounted) return;
      unawaited(_syncAfterOnline());
    });
    _dissolvedSub = widget.auth.ws.onGroupDissolved.listen(_onGroupDissolved);
    _addedSub = widget.auth.ws.onConversationAdded.listen(_onConversationAdded);
    _removedSub =
        widget.auth.ws.onConversationRemoved.listen(_onConversationRemoved);
    _updatedSub =
        widget.auth.ws.onConversationUpdated.listen(_onConversationUpdated);
    _patchedSub =
        widget.auth.onConversationPatched.listen(_applyConversationItemUpdate);
    _groupKeySub = widget.auth.onGroupKeyReady.listen((convId) {
      unawaited(_refreshPreviewFor(convId));
    });
  }

  Future<void> _refreshPreviewFor(String conversationId) async {
    if (!mounted) return;
    final index = _items.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;
    final item = _items[index];
    final last = item.lastMessage;
    if (last == null) return;
    final quick = widget.auth.previewIfCached(last);
    final preview = quick ??
        await widget.auth.decryptPreview(
          item,
          last,
          cachedThread: _messageCache[item.id],
        );
    if (!mounted) return;
    setState(() => _previews[item.id] = preview);
  }

  void _onConversationUpdated(ConversationUpdatedFrame frame) {
    if (!mounted) return;
    try {
      _applyConversationItemUpdate(
        ConversationItem.fromJson(frame.conversation),
      );
    } catch (_) {}
  }

  void _applyConversationItemUpdate(ConversationItem conv) {
    if (!mounted) return;
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
    WidgetsBinding.instance.removeObserver(this);
    widget.pendingPushConversation?.removeListener(_onPendingPushConversation);
    _msgSub?.cancel();
    _connSub?.cancel();
    _dissolvedSub?.cancel();
    _addedSub?.cancel();
    _removedSub?.cancel();
    _updatedSub?.cancel();
    _patchedSub?.cancel();
    _realtimeRestoredSub?.cancel();
    _groupKeySub?.cancel();
    _connSub?.cancel();
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

    widget.auth.prepareGroupConversation(conv);

    final existing = _items.indexWhere((c) => c.id == conv.id);
    if (existing >= 0) {
      var preview = '暂无消息';
      if (conv.lastMessage != null) {
        preview = await widget.auth.decryptPreview(conv, conv.lastMessage!);
      }
      if (!mounted) return;
      setState(() {
        _items[existing] = conv;
        if (conv.lastMessage != null) {
          _previews[conv.id] = preview;
        }
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

  String _quickPreview(
    ConversationItem item,
    String meId,
    ChatMessage msg,
  ) {
    if (msg.type == 'system') return msg.ciphertext;
    final String body;
    if (msg.type == 'announcement') {
      body = AnnouncementPayload.previewFromPlaintext(msg.plaintext);
    } else if (msg.type == 'text') {
      body = ChatMessage.decryptPlaceholder;
    } else {
      body = MediaPayload.previewLabel('', msg.type);
    }
    if (item.type != 'group') return body;
    return '${_senderName(item, meId, msg.senderId)}: $body';
  }

  void _onIncomingMessage(ChatMessage msg) {
    if (!mounted) return;

    final me = widget.auth.currentUser;
    if (me == null) return;

    final index = _items.indexWhere((c) => c.id == msg.conversationId);
    if (index < 0) {
      _bumpUnreadForIncoming(msg);
      _load();
      return;
    }

    final conv = _items[index];
    if (conv.type == 'group' &&
        msg.type != 'system' &&
        msg.epoch < conv.joinedEpochFor(me.id)) {
      return;
    }

    if (msg.senderId == me.id && conv.type != 'group') {
      unawaited(_applyOwnMessagePreview(conv, msg));
      return;
    }

    _bumpUnreadForIncoming(msg);

    final quick = _quickPreview(conv, me.id, msg);
    final updated = conv.copyWith(lastMessage: msg);
    setState(() {
      _previews[conv.id] = quick;
      _items[index] = updated;
      _items = sortConversationsByPin(_items, _pinnedIds);
    });

    unawaited(_finalizeIncomingMessage(conv, updated, msg));
  }

  /// 实时未读角标：不等待解密，避免 _refreshUnreadCounts 抢先清零。
  void _bumpUnreadForIncoming(ChatMessage msg) {
    if (msg.type == 'announcement' || msg.type == 'system') return;
    final me = widget.auth.currentUser;
    if (me == null || msg.senderId == me.id) return;
    if (widget.auth.isActivelyViewingConversation(msg.conversationId)) {
      if (mounted) setState(() => _unreadCounts[msg.conversationId] = 0);
      return;
    }
    unawaited(widget.auth.noteIncomingMessage(msg));
    if (!mounted) return;
    setState(() {
      _unreadCounts[msg.conversationId] =
          (_unreadCounts[msg.conversationId] ?? 0) + 1;
    });
  }

  /// 解密、落盘缓存，再更新预览（避免刷新/进聊天后无法解密）。
  Future<void> _finalizeIncomingMessage(
    ConversationItem conv,
    ConversationItem updated,
    ChatMessage msg,
  ) async {
    if (msg.type == 'announcement' && conv.type == 'group') {
      if (!mounted) return;
      final annUnread = await widget.auth.hasUnreadAnnouncementFor(updated);
      if (!mounted) return;
      setState(() => _announcementUnread[msg.conversationId] = annUnread);
      return;
    }

    final preview = await widget.auth.decryptPreview(conv, msg);
    if (!mounted) return;

    final storedPt =
        await widget.auth.cachedPlaintextForMessage(conv.id, msg.id);
    final refreshed = updated.copyWith(lastMessage: msg);
    setState(() {
      _previews[conv.id] = preview;
      if (storedPt != null) {
        _upsertCachedMessage(conv.id, msg, storedPt);
      } else {
        _upsertCachedMessageSkeleton(conv.id, msg);
      }
      final idx = _items.indexWhere((c) => c.id == conv.id);
      if (idx >= 0) {
        _items[idx] = refreshed;
      }
      _items = sortConversationsByPin(_items, _pinnedIds);
    });
  }

  Future<void> _applyOwnMessagePreview(
    ConversationItem conv,
    ChatMessage msg,
  ) async {
    final stored =
        await widget.auth.cachedPlaintextForMessage(conv.id, msg.id);
    final preview = stored ??
        (msg.type == 'text'
            ? ChatMessage.decryptPlaceholder
            : MediaPayload.previewLabel('', msg.type));
    if (!mounted) return;
    final updated = conv.copyWith(lastMessage: msg);
    setState(() {
      _previews[conv.id] = preview;
      if (stored != null) {
        _upsertCachedMessage(conv.id, msg, stored);
      } else {
        _upsertCachedMessageSkeleton(conv.id, msg);
      }
      final idx = _items.indexWhere((c) => c.id == conv.id);
      if (idx >= 0) {
        _items[idx] = updated;
      }
      _items = sortConversationsByPin(_items, _pinnedIds);
    });
  }

  Future<void> _refreshPinOrder() async {
    _pinnedIds = await widget.auth.pinnedConversationIds();
    if (!mounted) return;
    setState(() {
      _items = sortConversationsByPin(_items, _pinnedIds);
    });
  }

  Future<void> _loadMessageCaches(List<ConversationItem> items) async {
    final cache = await widget.auth.loadCachedMessagesForConversations(
      items.map((c) => c.id),
    );
    if (!mounted) return;
    setState(() {
      _messageCache
        ..clear()
        ..addAll(cache);
    });
  }

  Future<void> _reloadMessageCache(String conversationId) async {
    final msgs = await widget.auth.loadCachedMessages(conversationId);
    if (!mounted) return;
    setState(() {
      if (msgs.isEmpty) {
        _messageCache.remove(conversationId);
      } else {
        _messageCache[conversationId] = msgs;
      }
    });
  }

  void _upsertCachedMessage(
    String conversationId,
    ChatMessage msg,
    String plaintext,
  ) {
    if (msg.type != 'system' &&
        msg.type != 'announcement' &&
        (ChatMessage.isDecryptPlaceholder(plaintext) ||
            ChatMessage.isDecryptFailure(plaintext))) {
      _upsertCachedMessageSkeleton(conversationId, msg);
      return;
    }
    final stored = msg.type == 'system'
        ? msg.copyWith(plaintext: msg.ciphertext)
        : msg.type == 'announcement'
            ? msg
            : msg.copyWith(plaintext: plaintext);
    final existing = List<ChatMessage>.from(_messageCache[conversationId] ?? []);
    final i = existing.indexWhere((m) => m.id == msg.id);
    if (i >= 0) {
      existing[i] = stored;
    } else {
      existing.add(stored);
    }
    existing.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messageCache[conversationId] = existing;
  }

  /// 仅写入密文骨架，避免占位符污染内存缓存。
  void _upsertCachedMessageSkeleton(String conversationId, ChatMessage msg) {
    final skeleton = msg.type == 'system'
        ? msg.copyWith(plaintext: msg.ciphertext)
        : msg.forCacheWithoutPlaintext;
    final existing = List<ChatMessage>.from(_messageCache[conversationId] ?? []);
    final i = existing.indexWhere((m) => m.id == msg.id);
    if (i >= 0) {
      final prev = existing[i];
      existing[i] = ChatMessage(
        id: prev.id,
        conversationId: prev.conversationId,
        senderId: msg.senderId,
        type: msg.type,
        ciphertext: msg.ciphertext.isNotEmpty ? msg.ciphertext : prev.ciphertext,
        createdAt: msg.createdAt,
        epoch: msg.epoch,
        fileId: msg.fileId ?? prev.fileId,
      );
    } else {
      existing.add(skeleton);
    }
    existing.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messageCache[conversationId] = existing;
  }

  Future<void> _refreshUnreadCounts() async {
    final counts = await widget.auth.unreadCountsFor(
      _items.map((c) => c.id),
    );
    final annUnread = <String, bool>{};
    for (final item in _items) {
      if (item.type != 'group') continue;
      annUnread[item.id] = await widget.auth.hasUnreadAnnouncementFor(item);
    }
    if (!mounted) return;
    setState(() {
      _unreadCounts..clear..addAll(counts);
      _announcementUnread
        ..clear
        ..addAll(annUnread);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnResume());
    }
  }

  /// 从系统桌面回到 App：拉最新会话列表与漏收消息，更新首页预览。
  Future<void> _refreshOnResume() async {
    if (_resumeRefreshInFlight || !mounted) return;
    _resumeRefreshInFlight = true;
    try {
      await widget.auth.wakeRealtimeFromBackground();
      if (_items.isEmpty) {
        await _load();
        return;
      }
      await _refreshListFromServer(silent: true);
    } finally {
      _resumeRefreshInFlight = false;
    }
  }

  /// 从服务端同步会话列表、漏收消息，并刷新首页预览/未读。
  Future<void> _refreshListFromServer({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    try {
      final pinned = await widget.auth.pinnedConversationIds();
      final items = await widget.auth.listAllConversations();
      if (!mounted) return;
      await widget.auth.syncMissedMessages(items);
      if (!mounted) return;
      await _applyConversationListUpdate(items, pinned);
      if (!mounted) return;
      await _refreshUnreadCounts();
    } catch (_) {
      // 保留当前列表
    } finally {
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _applyConversationListUpdate(
    List<ConversationItem> items,
    List<String> pinned,
  ) async {
    final sorted = sortConversationsByPin(items, pinned);
    final msgCaches = await widget.auth.loadCachedMessagesForConversations(
      items.map((c) => c.id),
    );
    final previews = <String, String>{..._previews};
    for (final item in items) {
      final last = item.lastMessage;
      if (last == null) continue;
      ConversationItem? prev;
      for (final c in _items) {
        if (c.id == item.id) {
          prev = c;
          break;
        }
      }
      final lastChanged = prev?.lastMessage?.id != last.id;
      if (!lastChanged && previews.containsKey(item.id)) continue;

      if (item.type == 'group') {
        widget.auth.prepareGroupConversation(item);
        await widget.auth.ensureGroupKeys(
          item,
          epochs: [last.epoch],
        );
      }
      final quick = widget.auth.previewIfCached(last);
      previews[item.id] = quick ??
          await widget.auth.decryptPreview(
            item,
            last,
            cachedThread: msgCaches[item.id],
          );
    }
    if (!mounted) return;
    setState(() {
      _pinnedIds = pinned;
      _items = sorted;
      _previews
        ..clear()
        ..addAll(previews);
      for (final id in {...msgCaches.keys, ..._messageCache.keys}) {
        final persistent = msgCaches[id] ?? [];
        final memory = _messageCache[id] ?? [];
        if (persistent.isEmpty && memory.isEmpty) {
          _messageCache.remove(id);
        } else {
          _messageCache[id] = ChatThreadLoader.merge(persistent, memory);
        }
      }
      _syncOfflineNotice();
    });
  }

  /// 重连后拉取离线消息并刷新未读角标。
  Future<void> _syncAfterOnline() async {
    if (_items.isEmpty || _syncAfterOnlineInFlight) return;
    _syncAfterOnlineInFlight = true;
    try {
      await _refreshListFromServer(silent: true);
    } finally {
      _syncAfterOnlineInFlight = false;
    }
  }

  List<ConversationItem> _visibleItems(String meId) {
    return widget.auth.filterVisibleConversations(_items, _hiddenIds);
  }

  Future<void> _pinConversation(ConversationItem item, bool pin) async {
    await widget.auth.setConversationPinned(item.id, pinned: pin);
    _pinnedIds = await widget.auth.pinnedConversationIds();
    if (!mounted) return;
    setState(() => _items = sortConversationsByPin(_items, _pinnedIds));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pin ? '已置顶' : '已取消置顶')),
    );
  }

  Future<void> _markConversationRead(ConversationItem item) async {
    await widget.auth.markConversationRead(item.id);
    if (!mounted) return;
    setState(() => _unreadCounts[item.id] = 0);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已标记为已读')),
    );
  }

  Future<void> _showConversationActionMenu(
    BuildContext context,
    ConversationItem item,
    bool isPinned, {
    Offset? anchor,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset menuAnchor;
    if (anchor != null) {
      menuAnchor = anchor;
    } else {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      menuAnchor = box.localToGlobal(box.size.center(Offset.zero));
    }
    final position = RelativeRect.fromRect(
      Rect.fromCenter(center: menuAnchor, width: 0, height: 0),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: _menuRow(
            isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            isPinned ? '取消置顶' : '置顶',
          ),
        ),
        PopupMenuItem(
          value: 'read',
          child: _menuRow(Icons.done_all, '标记已读'),
        ),
        PopupMenuItem(
          value: 'delete',
          child: _menuRow(Icons.delete_outline, '删除', color: Colors.red),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        await _pinConversation(item, !isPinned);
      case 'read':
        await _markConversationRead(item);
      case 'delete':
        await _deleteConversation(item);
    }
  }

  Widget _menuRow(IconData icon, String label, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: color != null ? TextStyle(color: color) : null),
      ],
    );
  }

  Future<void> _deleteConversation(ConversationItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('从列表移除「${item.displayTitle(widget.auth.currentUser!.id)}」？本地消息仍会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.auth.hideConversationFromList(item.id);
    if (!mounted) return;
    setState(() {
      _hiddenIds.add(item.id);
      _unreadCounts.remove(item.id);
    });
  }


  Future<void> _load() async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    try {
      await _loadImpl();
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _loadImpl() async {
    final hadItems = _items.isNotEmpty;
    if (!hadItems) {
      final cached = await widget.auth.listCachedConversations();
      if (cached.isNotEmpty && mounted) {
        final pinned = await widget.auth.pinnedConversationIds();
        _hiddenIds = await widget.auth.hiddenConversationIds();
        setState(() {
          _pinnedIds = pinned;
          _items = sortConversationsByPin(cached, pinned);
        });
        unawaited(_loadMessageCaches(cached));
        unawaited(_refreshUnreadCounts());
      }
    }

    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      _hiddenIds = await widget.auth.hiddenConversationIds();
      final wsConnect = widget.auth.ensureRealtimeConnected();

      final pinned = await widget.auth.pinnedConversationIds();
      final items = await widget.auth
          .listAllConversations()
          .timeout(const Duration(seconds: 12));
      await wsConnect;
      final sorted = sortConversationsByPin(items, pinned);
      final msgCaches = await widget.auth.loadCachedMessagesForConversations(
        items.map((c) => c.id),
      );
      final previews = <String, String>{};
      for (final item in items) {
        final last = item.lastMessage;
        if (last == null) continue;
        final quick = widget.auth.previewIfCached(last);
        if (quick != null) {
          previews[item.id] = quick;
        }
      }
      for (final item in items) {
        if (previews.containsKey(item.id)) continue;
        final last = item.lastMessage;
        if (last == null) continue;
        if (item.type == 'group') {
          widget.auth.prepareGroupConversation(item);
          await widget.auth.ensureGroupKeys(
            item,
            epochs: [last.epoch],
          );
        }
        previews[item.id] = await widget.auth.decryptPreview(
          item,
          last,
          cachedThread: msgCaches[item.id],
        );
      }
      if (!mounted) return;
      setState(() {
        _pinnedIds = pinned;
        _items = sorted;
        _previews
          ..clear()
          ..addAll(previews);
        _syncOfflineNotice();
      });
      await widget.auth.syncMissedMessages(sorted);
      if (!mounted) return;
      unawaited(_loadMessageCaches(sorted));
      for (final item in sorted) {
        if (item.type == 'group') {
          unawaited(widget.auth.ensureGroupMemberDirectory(item));
        }
      }
      unawaited(_refreshUnreadCounts());
    } catch (e) {
      if (!mounted) return;
      if (_items.isEmpty) {
        final cached = await widget.auth.listCachedConversations();
        final pinned = await widget.auth.pinnedConversationIds();
        if (cached.isNotEmpty) {
          setState(() {
            _pinnedIds = pinned;
            _items = sortConversationsByPin(cached, pinned);
            _error = null;
            _offlineNotice = '网络不可用，已显示本地缓存';
          });
          unawaited(_loadMessageCaches(cached));
          unawaited(_refreshUnreadCounts());
        } else {
          setState(() => _error = e.toString());
        }
      } else {
        setState(() {
          _error = null;
          _offlineNotice = '刷新失败，仍显示上次数据';
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _onPendingPushConversation() {
    final id = widget.pendingPushConversation?.value;
    if (id == null || id.isEmpty) return;
    widget.pendingPushConversation!.value = null;
    unawaited(_openConversationById(id));
  }

  Future<void> _openConversationById(String conversationId) async {
    ConversationItem? conv;
    for (final c in _items) {
      if (c.id == conversationId) {
        conv = c;
        break;
      }
    }
    if (conv == null) {
      await _load();
      for (final c in _items) {
        if (c.id == conversationId) {
          conv = c;
          break;
        }
      }
    }
    if (conv != null && mounted) {
      await _openChat(conv);
    }
  }

  Future<void> _openChat(ConversationItem conv, {String? focusMessageId}) async {
    if (_hiddenIds.contains(conv.id)) {
      await widget.auth.restoreConversationToList(conv.id);
      if (!mounted) return;
      setState(() => _hiddenIds.remove(conv.id));
    }
    var item = conv;
    if (conv.isArchived) {
      final reactivated = await widget.auth.tryReactivateConversation(conv);
      if (reactivated != null) item = reactivated;
    }
    final initialUnread = _unreadCounts[item.id] ?? 0;
    if (mounted && initialUnread > 0) {
      setState(() => _unreadCounts[item.id] = 0);
    }
    final result = await Navigator.of(context).push<Object?>(
      appPageRoute(
        wrapNavigationPopScope: false,
        builder: (_) => ChatScreen(
          auth: widget.auth,
          conversation: item,
          notification: widget.notification,
          initialUnreadCount: initialUnread,
          initialFocusMessageId: focusMessageId,
        ),
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
      await _reloadMessageCache(conv.id);
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
    await _reloadMessageCache(conv.id);
    await _refreshUnreadCounts();
    await _refreshPinOrder();
  }

  Future<void> _openProfile() async {
    final result = await Navigator.of(context).push<Object?>(
      appPageRoute(
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

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<Object?>(
      appPageRoute(
        builder: (_) => SettingsScreen(
          auth: widget.auth,
          notification: widget.notification,
        ),
      ),
    );
    if (result == 'logout' && mounted) {
      await widget.onLogout();
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await widget.onLogout();
    }
  }

  Future<void> _showAccountMenu() async {
    final me = widget.auth.currentUser!;
    await Navigator.of(context).push<void>(
      slideFromLeftRoute<void>(
        page: AccountPanelScreen(
          user: me,
          onProfile: () {
            Navigator.of(context).pop();
            unawaited(_openProfile());
          },
          onSettings: () {
            Navigator.of(context).pop();
            unawaited(_openSettings());
          },
          onLogout: () {
            Navigator.of(context).pop();
            unawaited(_confirmLogout());
          },
        ),
      ),
    );
  }

  Future<void> _openCreateMenu() async {
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
      appPageRoute(
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

  List<ConversationItem> _filteredItems(String meId) => _visibleItems(meId);

  String _senderName(ConversationItem item, String meId, String senderId) {
    if (item.type == 'group') {
      return widget.auth.groupSenderLabel(item, meId, senderId);
    }
    if (senderId == meId) return '我';
    for (final m in item.members) {
      if (m.userId == senderId) return m.username;
    }
    return '?';
  }

  String _formatLastMessagePreview(
    ConversationItem item,
    String meId,
    String preview,
    ChatMessage? last,
  ) {
    var text = preview;
    if (last?.type == 'announcement') {
      text = AnnouncementPayload.previewFromPlaintext(
        preview == ChatMessage.decryptPlaceholder ? null : preview,
      );
    } else if (last != null && last.type != 'system') {
      text = MediaPayload.previewLabel(preview, last.type);
    }
    if (item.type != 'group' || last == null || last.type == 'system') {
      return text;
    }
    return '${_senderName(item, meId, last.senderId)}: $text';
  }

  String _subtitleFor(
    ConversationItem item,
    String meId,
    String preview,
  ) {
    final hidden = _hiddenIds.contains(item.id);
    if (item.isArchived) {
      final body = '已退出 · $preview';
      return hidden ? '已从列表移除 · $body' : body;
    }
    if (hidden) return '已从列表移除 · $preview';
    return preview;
  }

  Future<void> _openHomeSearch() async {
    final me = widget.auth.currentUser;
    if (me == null) return;
    await Navigator.of(context).push<void>(
      appPageRoute(
        builder: (_) => HomeSearchScreen(
          auth: widget.auth,
          conversations: _visibleItems(me.id),
          messageCache: _messageCache,
          onOpenChat: (conv, {messageId}) =>
              _openChat(conv, focusMessageId: messageId),
        ),
      ),
    );
  }

  Widget _buildSearchEntry() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => unawaited(_openHomeSearch()),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.search, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '搜索',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('未登录')),
      );
    }
    final visible = _filteredItems(me.id);
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => unawaited(_showAccountMenu()),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                UserAvatar(
                  name: me.username,
                  imageUrl: me.avatarUrl,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '你好，${me.username}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      HomeConnectionStatus(
                        wsConnected: widget.auth.ws.isConnected,
                        onReconnect: widget.auth.ws.isConnected
                            ? null
                            : () => unawaited(
                                widget.auth.ensureRealtimeConnected(),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '发起聊天',
            onPressed: () => unawaited(_openCreateMenu()),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_offlineNotice != null)
            OfflineBanner(
              message: _offlineNotice!,
              onRetry: () => unawaited(
                widget.auth.ensureRealtimeConnected().then((_) {
                  if (mounted) setState(_syncOfflineNotice);
                }),
              ),
            ),
          if (_refreshing)
            const LinearProgressIndicator(minHeight: 2),
          _buildSearchEntry(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _error != null && _items.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_error!),
                            ),
                          ],
                        )
                      : visible.isEmpty
                          ? ListView(
                              children: [
                                SizedBox(height: _items.isEmpty ? 120 : 80),
                                Center(
                                  child: Text(
                                    _items.isEmpty
                                        ? (_refreshing
                                            ? '正在同步会话…'
                                            : '暂无会话，点右上角 + 发起聊天')
                                        : '暂无会话，点右上角 + 发起聊天',
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = visible[index];
                                final last = item.lastMessage;
                                final rawPreview = last == null
                                    ? '暂无消息'
                                    : (_previews[item.id] ??
                                        (last.type == 'announcement'
                                            ? '[群公告]'
                                            : last.displayText));
                                final preview = _formatLastMessagePreview(
                                  item,
                                  me.id,
                                  rawPreview,
                                  last,
                                );
                                final peerName = item.displayTitle(me.id);
                                final isPinned = _pinnedIds.contains(item.id);
                                final unread = _unreadCounts[item.id] ?? 0;
                                final annUnread =
                                    _announcementUnread[item.id] ?? false;
                                final subtitle = _subtitleFor(item, me.id, preview);
                                return SwipeActionTile(
                                  key: ValueKey(item.id),
                                  onLongPress: (details) => unawaited(
                                    _showConversationActionMenu(
                                      context,
                                      item,
                                      isPinned,
                                      anchor: details.globalPosition,
                                    ),
                                  ),
                                  actions: [
                                    SwipeAction(
                                      icon: isPinned
                                          ? Icons.push_pin_outlined
                                          : Icons.push_pin,
                                      label: isPinned ? '取消' : '置顶',
                                      color: Colors.orange,
                                      onTap: () => unawaited(
                                        _pinConversation(item, !isPinned),
                                      ),
                                    ),
                                    SwipeAction(
                                      icon: Icons.done_all,
                                      label: '已读',
                                      color: Colors.blue,
                                      onTap: () => unawaited(
                                        _markConversationRead(item),
                                      ),
                                    ),
                                    SwipeAction(
                                      icon: Icons.delete_outline,
                                      label: '删除',
                                      color: Colors.red,
                                      onTap: () => unawaited(
                                        _deleteConversation(item),
                                      ),
                                    ),
                                  ],
                                  child: _ConversationRow(
                                    lastMessageId: last?.id,
                                    child: ListTile(
                                      leading: UserAvatar(
                                        name: peerName,
                                        imageUrl: item.displayAvatarUrl(me.id),
                                        badgeCount: unread,
                                      ),
                                      title: Row(
                                        children: [
                                          if (isPinned)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(right: 4),
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
                                          if (item.type == 'group' && annUnread)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4,
                                              ),
                                              child: Icon(
                                                Icons.campaign,
                                                size: 16,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                            ),
                                          if (last != null) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              MessageTimeFormat.formatList(
                                                last.createdAt,
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    fontSize: 12,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      subtitle: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      onTap: () => _openChat(item),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 新消息到达时短暂高亮会话行，避免列表更新过于生硬。
class _ConversationRow extends StatefulWidget {
  const _ConversationRow({
    required this.lastMessageId,
    required this.child,
  });

  final String? lastMessageId;
  final Widget child;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow>
    with SingleTickerProviderStateMixin {
  String? _seenMessageId;
  late final AnimationController _pulse;
  late final Animation<double> _pulseStrength;

  @override
  void initState() {
    super.initState();
    _seenMessageId = widget.lastMessageId;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 880),
    );
    _pulseStrength = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 32,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 68,
      ),
    ]).animate(_pulse);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _playNewMessageGlow() {
    _pulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(_ConversationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.lastMessageId;
    if (incoming == null ||
        incoming.isEmpty ||
        incoming == _seenMessageId) {
      return;
    }
    _seenMessageId = incoming;
    _playNewMessageGlow();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _pulseStrength,
      builder: (context, child) {
        final glow = _pulseStrength.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(
              Colors.transparent,
              scheme.primary.withValues(alpha: 0.07),
              glow,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}