import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/ws_service.dart';
import '../utils/media_payload.dart';
import '../utils/message_time.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/marquee_text.dart';
import '../widgets/offline_banner.dart';
import '../widgets/user_avatar.dart';
import 'chat_settings_screen.dart';
import 'group_manage_screen.dart';
import 'user_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  late ConversationItem _conversation;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  String? _error;
  int _historyEpoch = 0;
  bool _tailPinned = true;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<GroupDissolvedFrame>? _dissolvedSub;
  StreamSubscription<EpochUpdatedFrame>? _epochSub;
  StreamSubscription<ConversationRemovedFrame>? _removedSub;
  StreamSubscription<ConversationUpdatedFrame>? _updatedSub;
  StreamSubscription<ConversationAddedFrame>? _addedSub;
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _voiceStartInProgress = false;
  bool _voiceCancelOnStart = false;
  bool _sending = false;
  DateTime? _recordStartedAt;
  Timer? _voiceLimitTimer;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    widget.auth.setOpenConversation(_conversation.id);
    _msgSub = widget.auth.ws.onMessage.listen((msg) {
      unawaited(_onIncomingMessage(msg));
    });
    _connSub = widget.auth.ws.onConnectionChanged.listen((connected) {
      if (!mounted) return;
      setState(() {});
      if (connected && !_conversation.isArchived) {
        widget.auth.ws.joinConversation(_conversation.id);
      }
    });
    if (!_conversation.isArchived) {
      widget.auth.ws.joinConversation(_conversation.id);
    }
    _scroll.addListener(() => _tailPinned = _isNearBottom());
    _bootstrap();
    _dissolvedSub = widget.auth.ws.onGroupDissolved.listen(_onGroupDissolved);
    _epochSub = widget.auth.ws.onEpochUpdated.listen(_onEpochUpdated);
    _removedSub =
        widget.auth.ws.onConversationRemoved.listen(_onConversationRemoved);
    _updatedSub =
        widget.auth.ws.onConversationUpdated.listen(_onConversationUpdated);
    _addedSub =
        widget.auth.ws.onConversationAdded.listen(_onConversationAdded);
  }

  @override
  void dispose() {
    widget.auth.setOpenConversation(null);
    _msgSub?.cancel();
    _connSub?.cancel();
    _dissolvedSub?.cancel();
    _epochSub?.cancel();
    _removedSub?.cancel();
    _updatedSub?.cancel();
    _addedSub?.cancel();
    _voiceLimitTimer?.cancel();
    if (_recording || _voiceStartInProgress) {
      unawaited(_recorder.stop());
      _recording = false;
      _voiceStartInProgress = false;
      _voiceCancelOnStart = true;
    }
    unawaited(_recorder.dispose());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _isStale(int epoch) => !mounted || epoch != _historyEpoch;

  void _bumpHistoryEpoch() => _historyEpoch++;

  bool _isNearBottom([double threshold = 80]) {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels <= threshold;
  }

  bool _tailChanged(List<ChatMessage> before, List<ChatMessage> after) {
    if (after.isEmpty) return false;
    if (before.isEmpty) return true;
    if (after.length != before.length) return true;
    return after.last.id != before.last.id;
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> primary,
    List<ChatMessage> secondary,
  ) {
    final byId = {for (final m in primary) m.id: m};
    for (final cached in secondary) {
      final remote = byId[cached.id];
      if (remote == null) {
        byId[cached.id] = cached;
      } else {
        final pt = cached.plaintext;
        if (pt != null && pt.isNotEmpty) {
          byId[cached.id] = remote.copyWith(plaintext: pt);
        }
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<ChatMessage> _displayableMessages(List<ChatMessage> msgs) {
    return msgs
        .map(
          (m) => m.type == 'system'
              ? m.copyWith(plaintext: m.plaintext ?? m.ciphertext)
              : m,
        )
        .toList();
  }

  Future<List<ChatMessage>> _fetchMergedMessages(
    List<ChatMessage> cached,
  ) async {
    try {
      final remote = await widget.auth.conversations.listMessages(
        _conversation.id,
        limit: 100,
      );
      return cached.isEmpty ? remote : _mergeMessages(remote, cached);
    } catch (_) {
      return cached;
    }
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (animated) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(0);
      }
    });
  }

  Future<void> _bootstrap() async {
    final reactivated =
        await widget.auth.tryReactivateConversation(_conversation);
    if (reactivated != null && mounted) {
      setState(() => _conversation = reactivated);
    }
    unawaited(_refreshConversationMetadata());
    await _loadHistory();
  }

  Future<void> _refreshConversationMetadata() async {
    if (_conversation.isArchived) return;
    try {
      final fresh = await widget.auth.refreshConversation(_conversation);
      if (!mounted || _conversation.isArchived) return;
      setState(() => _conversation = fresh);
    } catch (_) {}
  }

  Future<void> _markRead() async {
    if (_messages.isEmpty) return;
    await widget.auth.markConversationRead(
      _conversation.id,
      upTo: _messages.last.createdAt,
    );
  }

  Widget _buildMessageList({
    required BuildContext context,
    required User me,
    required bool isGroup,
    required bool isArchived,
  }) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '暂无消息',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                isArchived
                    ? '此会话暂无历史消息'
                    : '下方输入内容，发送第一条消息',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msgIndex = _messages.length - 1 - index;
        final msg = _messages[msgIndex];
        final prev = msgIndex > 0 ? _messages[msgIndex - 1] : null;
        return _buildMessageItem(
          context: context,
          me: me,
          msg: msg,
          prev: prev,
          isGroup: isGroup,
        );
      },
    );
  }

  Future<void> _loadHistory() async {
    final epoch = _historyEpoch;
    final archived = _conversation.isArchived;

    if (_messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      var msgs = await widget.auth.loadCachedMessages(_conversation.id);
      if (_isStale(epoch)) return;

      if (_conversation.type == 'group' && msgs.isNotEmpty) {
        try {
          await widget.auth.ensureGroupKeysForMessages(_conversation, msgs);
        } catch (_) {}
      }
      if (_isStale(epoch)) return;

      final fullyLocal = msgs.isNotEmpty &&
          await widget.auth.cachedMessagesFullyAvailable(msgs);

      if (msgs.isNotEmpty) {
        var local = await widget.auth.decryptMessagesLocal(_conversation, msgs);
        if (_isStale(epoch)) return;
        if (_messages.isEmpty) {
          setState(() {
            _messages = _displayableMessages(local);
            _loading = false;
            _tailPinned = true;
          });
        }
        if (fullyLocal) {
          setState(() {
            _messages = local;
            _error = null;
          });
          unawaited(widget.auth.cacheMessages(_conversation.id, local));
          return;
        }
      }

      if (archived) {
        try {
          msgs = await _fetchMergedMessages(msgs);
          if (!_isStale(epoch)) {
            final local =
                await widget.auth.decryptMessagesLocal(_conversation, msgs);
            setState(() {
              _messages = local;
              _error = null;
            });
            if (_messages.isNotEmpty) {
              await widget.auth.cacheMessages(_conversation.id, _messages);
            }
          }
        } catch (_) {
          if (_messages.isEmpty && msgs.isNotEmpty) {
            setState(() {
              _messages = _displayableMessages(msgs);
              _error = null;
            });
          }
        }
        return;
      }

      msgs = await _fetchMergedMessages(msgs);
      if (_isStale(epoch) || _conversation.isArchived != archived) return;

      if (_conversation.type == 'group') {
        await widget.auth.ensureGroupKeysForMessages(_conversation, msgs);
      }
      if (_isStale(epoch) || _conversation.isArchived) return;

      final before = _messages;
      final decrypted =
          await widget.auth.decryptMessagesLocal(_conversation, msgs);
      if (_isStale(epoch)) return;

      final tailChanged = _tailChanged(before, decrypted);
      setState(() {
        _messages = decrypted;
      });
      await widget.auth.cacheMessages(_conversation.id, decrypted);
      if ((_tailPinned || before.isEmpty) && tailChanged) {
        _scrollToBottom(animated: _tailPinned && before.isNotEmpty);
      }
    } catch (e) {
      if (_isStale(epoch)) return;
      if (_messages.isEmpty) {
        final cached = await widget.auth.loadCachedMessages(_conversation.id);
        if (cached.isNotEmpty) {
          setState(() {
            _messages = _displayableMessages(cached);
            _error = null;
            _tailPinned = true;
          });
        } else {
          setState(() => _error = e.toString());
        }
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (!_isStale(epoch)) {
        setState(() => _loading = false);
        unawaited(_markRead());
      }
    }
  }

  Future<void> _archiveAndReload() async {
    _bumpHistoryEpoch();
    setState(() => _conversation = _conversation.copyWith(isArchived: true));
    await _loadHistory();
  }

  void _upsertMessage(ChatMessage msg, {bool persist = true}) {
    final i = _messages.indexWhere((m) => m.id == msg.id);
    _messages = i >= 0
        ? [
            ..._messages.sublist(0, i),
            msg,
            ..._messages.sublist(i + 1),
          ]
        : [..._messages, msg];
    if (persist && !ChatMessage.isDecryptPlaceholder(msg.plaintext)) {
      unawaited(widget.auth.cacheMessages(_conversation.id, _messages));
    }
  }

  Future<void> _onConversationAdded(ConversationAddedFrame frame) async {
    final conv = ConversationItem.fromJson(frame.conversation);
    if (conv.id != _conversation.id) return;
    if (!mounted) return;
    final active = await widget.auth.reactivateConversation(conv);
    if (!mounted) return;
    setState(() => _conversation = active);
    widget.auth.ws.joinConversation(active.id);
    await _loadHistory();
  }

  void _onConversationUpdated(ConversationUpdatedFrame frame) {
    if (!mounted) return;
    try {
      final conv = ConversationItem.fromJson(frame.conversation);
      if (conv.id != _conversation.id) return;
      setState(() {
        _conversation = widget.auth.mergeConversationUpdate(_conversation, conv);
      });
    } catch (_) {}
  }

  Future<void> _onEpochUpdated(EpochUpdatedFrame frame) async {
    if (frame.conversationId != _conversation.id) return;
    if (!mounted) return;
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (!mounted) return;
    setState(() => _conversation = fresh.copyWith(epoch: frame.epoch));
  }

  Future<void> _onConversationRemoved(ConversationRemovedFrame frame) async {
    if (frame.conversationId != _conversation.id) return;
    if (!mounted) return;
    final showUi = widget.auth.claimRemovalUi(frame.conversationId);
    await widget.auth.handleConversationRemoved(
      frame.conversationId,
      snapshot: _conversation,
      messages: _messages,
    );
    if (!mounted) return;
    await _archiveAndReload();
    if (!mounted || !showUi) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('你已被移出该群聊，仍可查看历史消息')),
    );
  }

  Future<void> _onGroupDissolved(GroupDissolvedFrame frame) async {
    if (frame.conversationId != _conversation.id) return;
    if (!mounted) return;

    final me = widget.auth.currentUser;
    if (me == null) return;
    final isSelf = frame.dissolvedBy == me.id;
    await widget.auth.handleGroupDissolved(frame.conversationId);

    if (!isSelf) {
      final name = frame.groupName.isNotEmpty
          ? frame.groupName
          : _conversation.displayTitle(me.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('群聊已解散'),
          content: Text('群聊「$name」已被解散'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop('dissolved');
    }
  }

  Future<void> _repairMessageMedia(String messageId) async {
    final i = _messages.indexWhere((m) => m.id == messageId);
    if (i < 0) return;
    final msg = _messages[i];
    final repaired =
        await widget.auth.repairMessageMedia(_conversation, msg);
    if (repaired == null || !mounted) return;
    setState(() {
      _messages = [
        ..._messages.sublist(0, i),
        repaired,
        ..._messages.sublist(i + 1),
      ];
    });
    unawaited(widget.auth.cacheMessages(_conversation.id, _messages));
  }

  Future<void> _onIncomingMessage(ChatMessage msg) async {
    if (_conversation.isArchived) return;
    if (msg.conversationId != _conversation.id) return;
    if (!mounted) return;

    if (msg.type == 'system') {
      setState(
        () => _upsertMessage(msg.copyWith(plaintext: msg.ciphertext)),
      );
    } else {
      setState(
        () => _upsertMessage(
          msg.copyWith(plaintext: ChatMessage.decryptPlaceholder),
          persist: false,
        ),
      );
      final decrypted =
          await widget.auth.decryptMessage(_conversation, msg);
      if (!mounted) return;
      setState(() => _upsertMessage(decrypted));
    }
    if (_tailPinned) _scrollToBottom();
    unawaited(_markRead());
  }

  String? _avatarUrlFor(String userId, User me) {
    if (userId == me.id) return me.avatarUrl;
    for (final m in _conversation.members) {
      if (m.userId == userId) return m.avatarUrl;
    }
    return null;
  }

  String _nameFor(String userId, User me) {
    if (userId == me.id) return me.username;
    for (final m in _conversation.members) {
      if (m.userId == userId) return m.username;
    }
    return '?';
  }

  ConversationMember? _memberFor(String userId) {
    for (final m in _conversation.members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  void _openUserDetail(String userId) {
    final me = widget.auth.currentUser;
    if (me == null || userId == me.id) return;

    final member = _memberFor(userId);
    if (member != null) {
      openUserDetailFromMember(
        context,
        auth: widget.auth,
        member: member,
        groupContext: _conversation.type == 'group' ? _conversation : null,
      );
    }
  }

  Future<void> _openChatSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatSettingsScreen(
          auth: widget.auth,
          conversation: _conversation,
        ),
      ),
    );
  }

  Future<void> _openConversationMenu() async {
    if (_conversation.type == 'group') {
      await _openGroupManage();
    } else {
      await _openChatSettings();
    }
  }

  Future<void> _sendMedia({
    required String type,
    required MediaPayload media,
    bool blockInput = true,
  }) async {
    final maxBytes = type == 'audio' ? kMaxAudioBytes : kMaxMediaBytes;
    if (media.bytes.length > maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == 'audio'
                ? '语音过大，请控制在 ${kMaxVoiceDuration.inSeconds} 秒以内'
                : '文件过大，请选择 8MB 以内的内容',
          ),
        ),
      );
      return;
    }
    if (blockInput) setState(() => _sending = true);
    try {
      final msg = await widget.auth.sendChatMessage(
        _conversation,
        media.encodePlaintext(),
        type: type,
      );
      if (!mounted) return;
      setState(() => _upsertMessage(msg));
      _tailPinned = true;
      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (blockInput && mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _sendMedia(
      type: 'image',
      media: MediaPayload(
        kind: 'image',
        mime: 'image/jpeg',
        name: file.name.isNotEmpty ? file.name : 'image.jpg',
        bytes: bytes,
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;
    await _sendMedia(
      type: 'file',
      media: MediaPayload(
        kind: 'file',
        mime: file.extension != null ? 'application/${file.extension}' : 'application/octet-stream',
        name: file.name,
        bytes: bytes,
      ),
    );
  }

  Future<bool> _startVoiceRecord() async {
    if (_recording || _voiceStartInProgress) return false;
    _voiceStartInProgress = true;
    try {
      if (_voiceCancelOnStart) {
        _voiceCancelOnStart = false;
        return false;
      }
      if (!await _recorder.hasPermission()) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能发送语音')),
        );
        return false;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return false;
      if (_voiceCancelOnStart) {
        _voiceCancelOnStart = false;
        await _recorder.stop();
        return false;
      }
      setState(() {
        _recording = true;
        _recordStartedAt = DateTime.now();
      });
      _voiceLimitTimer?.cancel();
      _voiceLimitTimer = Timer(kMaxVoiceDuration, () {
        if (_recording && mounted) {
          unawaited(_finishVoiceRecord(cancel: false));
        }
      });
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法开始录音：$e')),
        );
      }
      return false;
    } finally {
      _voiceStartInProgress = false;
    }
  }

  Future<void> _finishVoiceRecord({required bool cancel}) async {
    if (!_recording) {
      if (_voiceStartInProgress) {
        _voiceCancelOnStart = true;
      }
      return;
    }
    _voiceLimitTimer?.cancel();
    _voiceLimitTimer = null;
    final path = await _recorder.stop();
    final started = _recordStartedAt;
    if (mounted) {
      setState(() {
        _recording = false;
        _recordStartedAt = null;
      });
    }
    if (cancel || path == null) return;
    final durationMs = started == null
        ? null
        : DateTime.now().difference(started).inMilliseconds;
    if ((durationMs ?? 0) < 800) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('说话时间太短')),
        );
      }
      return;
    }
    final bytes = await File(path).readAsBytes();
    await _sendMedia(
      type: 'audio',
      blockInput: false,
      media: MediaPayload(
        kind: 'audio',
        mime: 'audio/m4a',
        name: 'voice.m4a',
        bytes: bytes,
        durationMs: durationMs,
      ),
    );
  }

  Future<void> _openGroupManage() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => GroupManageScreen(
          auth: widget.auth,
          conversation: _conversation,
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'left') {
      await _archiveAndReload();
      return;
    }
    if (result == 'dissolved') {
      await widget.auth.cacheMessages(_conversation.id, _messages);
      if (!mounted) return;
      Navigator.of(context).pop(result);
      return;
    }
    final fresh = await widget.auth.refreshConversation(_conversation);
    if (mounted) setState(() => _conversation = fresh);
    await _loadHistory();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    try {
      final msg = await widget.auth.sendChatMessage(
        _conversation,
        text,
      );
      if (!mounted) return;
      setState(() => _upsertMessage(msg));
      _tailPinned = true;
      _scrollToBottom(animated: true);
    } catch (e) {
      if (!mounted) return;
      _input.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _showEmojiPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('表情功能即将上线')),
    );
  }

  Widget _buildInputBar(BuildContext context, bool isArchived) {
    if (isArchived) return const SizedBox.shrink();

    return ChatInputBar(
      controller: _input,
      sending: _sending,
      onSend: _send,
      onVoiceHoldStart: _startVoiceRecord,
      onVoiceHoldEnd: _finishVoiceRecord,
      onImage: () => unawaited(_pickImage()),
      onFile: () => unawaited(_pickFile()),
      onEmoji: _showEmojiPlaceholder,
    );
  }

  Widget _buildMessageItem({
    required BuildContext context,
    required User me,
    required ChatMessage msg,
    required ChatMessage? prev,
    required bool isGroup,
  }) {
    final showTime = MessageTimeFormat.shouldShowDivider(
      prev?.createdAt,
      msg.createdAt,
    );
    final timeDivider = showTime
        ? MessageTimeDivider(
            label: MessageTimeFormat.formatDivider(msg.createdAt),
          )
        : null;

    Widget content;
    if (msg.type == 'system') {
      content = Center(
        child: Text(
          msg.displayText,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    } else {
      content = ChatBubble(
        msg: msg,
        mine: msg.senderId == me.id,
        isGroup: isGroup,
        me: me,
        senderTitle: _conversation.memberTitle(msg.senderId),
        nameFor: (userId) => _nameFor(userId, me),
        avatarUrlFor: (userId) => _avatarUrlFor(userId, me),
        onPeerTap: _openUserDetail,
        onMediaRetry: _repairMessageMedia,
      );
    }

    return Column(
      key: ValueKey(msg.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timeDivider != null) timeDivider,
        if (msg.type == 'system')
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: content,
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: content,
          ),
      ],
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
    final title = _conversation.displayTitle(me.id);
    final avatarUrl = _conversation.displayAvatarUrl(me.id);
    final isGroup = _conversation.type == 'group';
    ConversationMember? peerMember;
    if (!isGroup) {
      for (final m in _conversation.members) {
        if (m.userId != me.id) {
          peerMember = m;
          break;
        }
      }
    }
    final isArchived = _conversation.isArchived;
    return PopScope(
      canPop: !isArchived,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !isArchived || !mounted) return;
        Navigator.of(context).pop('left');
      },
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: peerMember != null
                ? () => _openUserDetail(peerMember!.userId)
                : null,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                UserAvatar(
                  name: title,
                  imageUrl: avatarUrl,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        text: title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (isGroup && !isArchived)
                        Text(
                          '${_conversation.members.length} 人',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (isArchived)
                        Text(
                          '已退出 · 只读',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!isArchived)
              IconButton(
                tooltip: '更多',
                icon: const Icon(Icons.menu),
                onPressed: _openConversationMenu,
              ),
          ],
        ),
        body: Column(
          children: [
            if (!widget.auth.ws.isConnected)
              OfflineBanner(
                message: '网络已断开，消息可能无法收发',
                onRetry: () => unawaited(widget.auth.reconnectRealtime()),
              ),
            if (isArchived)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('你已退出此群聊，仅可查看历史消息'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _buildMessageList(
                context: context,
                me: me,
                isGroup: isGroup,
                isArchived: isArchived,
              ),
            ),
            if (!isArchived)
              _buildInputBar(context, isArchived),
          ],
        ),
      ),
    );
  }
}
