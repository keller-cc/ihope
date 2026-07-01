import 'dart:async';
import 'dart:typed_data';

import '../crypto/chat_crypto.dart';
import '../crypto/e2ee_exception.dart';
import '../crypto/identity.dart';
import '../crypto/megolm_policy.dart';
import '../crypto/megolm_rotation_meta.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'auth_storage.dart';
import 'conversation_service.dart';
import 'ws_service.dart';

/// 群聊 GMK 生命周期：分发、同步、WS 事件处理。
class GroupKeyService {
  GroupKeyService({
    required this.conversations,
    required this.storage,
    required this.ws,
    required this.crypto,
    required this.refreshConversation,
    required this.getCurrentUser,
    required this.getOpenConversationId,
    required this.getCachedConversation,
    required this.cacheConversation,
  });

  final ConversationService conversations;
  final AuthStorage storage;
  final WsService ws;
  final ChatCrypto Function() crypto;
  final Future<ConversationItem> Function(ConversationItem) refreshConversation;
  final User? Function() getCurrentUser;
  final String? Function() getOpenConversationId;
  final ConversationItem? Function(String id) getCachedConversation;
  final void Function(ConversationItem) cacheConversation;

  final _gmkWaiters = <String, List<Completer<void>>>{};
  final _inFlight = <String, Future<void>>{};
  final _readyController = StreamController<String>.broadcast();

  StreamSubscription<KeyRelayFrame>? _keyRelaySub;
  StreamSubscription<GmkRequestFrame>? _gmkRequestSub;
  StreamSubscription<GmkUpdatedFrame>? _gmkUpdatedSub;
  StreamSubscription<EpochUpdatedFrame>? _epochSub;

  Stream<String> get onKeysReady => _readyController.stream;

  void attachWsHandlers() {
    detachWsHandlers();
    _keyRelaySub = ws.onKeyRelay.listen((f) => unawaited(_onKeyRelay(f)));
    _gmkRequestSub = ws.onGmkRequest.listen((f) => unawaited(_onGmkRequest(f)));
    _gmkUpdatedSub = ws.onGmkUpdated.listen((f) => unawaited(_onGmkUpdated(f)));
    _epochSub = ws.onEpochUpdated.listen((f) => unawaited(_onEpochUpdated(f)));
  }

  void detachWsHandlers() {
    unawaited(_keyRelaySub?.cancel());
    _keyRelaySub = null;
    unawaited(_gmkRequestSub?.cancel());
    _gmkRequestSub = null;
    unawaited(_gmkUpdatedSub?.cancel());
    _gmkUpdatedSub = null;
    unawaited(_epochSub?.cancel());
    _epochSub = null;
  }

  /// 打开会话时准备当前 epoch 密钥（不阻塞 UI）。
  void prepareForConversation(ConversationItem conversation) {
    if (conversation.type != 'group') return;
    unawaited(
      ensureKeys(conversation, epochs: [conversation.epoch]),
    );
  }

  /// 按消息涉及的历史 epoch 准备密钥。
  Future<void> prepareForMessages(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) {
    if (conversation.type != 'group' || messages.isEmpty) return Future.value();
    final epochs = messages.map((m) => m.epoch).toSet().toList();
    return ensureKeys(conversation, epochs: epochs);
  }

  /// 发送前 Megolm 定期轮换（100 条或 24 小时）。
  Future<ConversationItem> maybeRotateBeforeSend(
    ConversationItem conversation,
  ) async {
    if (conversation.type != 'group') return conversation;
    final me = getCurrentUser();
    if (me == null) return conversation;
    if (!await _shouldRotate(conversation.id)) return conversation;
    if (!await hasGmk(conversation.id, conversation.epoch)) {
      return conversation;
    }

    final result = await conversations.rotateGroupKeys(conversation.id);
    var updated = result.conversation.copyWith(epoch: result.epoch);
    cacheConversation(updated);
    final gmk = await crypto().rotateGroupEpoch(updated.id, result.epoch);
    await publishEpochKeys(updated, gmk);
    await resetRotationMeta(conversation.id);
    return refreshConversation(updated);
  }

  /// 记录本 epoch 内已发送群消息数（用于定期轮换）。
  Future<void> recordGroupMessageSent(String conversationId) async {
    final me = getCurrentUser();
    if (me == null) return;
    final meta = await storage.readMegolmRotationMeta(me.id, conversationId) ??
        MegolmRotationMeta.initial();
    await storage.writeMegolmRotationMeta(
      me.id,
      conversationId,
      MegolmRotationMeta(
        messageCount: meta.messageCount + 1,
        lastRotatedAt: meta.lastRotatedAt,
      ),
    );
  }

  Future<void> resetRotationMeta(String conversationId) async {
    final me = getCurrentUser();
    if (me == null) return;
    await storage.writeMegolmRotationMeta(
      me.id,
      conversationId,
      MegolmRotationMeta.initial(),
    );
  }

  Future<bool> _shouldRotate(String conversationId) async {
    final me = getCurrentUser();
    if (me == null) return false;
    final meta = await storage.readMegolmRotationMeta(me.id, conversationId) ??
        MegolmRotationMeta.initial();
    if (meta.messageCount >= MegolmRotationPolicy.maxMessagesPerEpoch) {
      return true;
    }
    return DateTime.now().difference(meta.lastRotatedAt) >=
        MegolmRotationPolicy.maxEpochAge;
  }

  /// 发送前必须就绪。
  Future<void> ensureReadyForSend(ConversationItem conversation) async {
    await ensureKeys(
      conversation,
      epochs: [conversation.epoch],
      waitForRelay: true,
    );
    if (!await hasGmk(conversation.id, conversation.epoch)) {
      throw E2eeException('群密钥尚未就绪，请稍后重试');
    }
  }

  Future<bool> hasGmk(String conversationId, int epoch) async {
    final me = getCurrentUser();
    if (me == null) return false;
    final raw = await storage.readGroupGmk(me.id, conversationId, epoch);
    return raw != null && raw.length == 32;
  }

  Future<void> ensureKeys(
    ConversationItem conversation, {
    List<int>? epochs,
    bool waitForRelay = false,
  }) async {
    if (conversation.type != 'group') return;
    final me = getCurrentUser();
    if (me == null) return;

    var conv = conversation;
    if (conv.members.isEmpty) {
      conv = await refreshConversation(conversation);
    }

    final needed = <int>{conv.epoch, ...?epochs};
    for (final epoch in needed) {
      await _ensureEpoch(conv, epoch, waitForRelay: waitForRelay);
    }
  }

  Future<void> ensureOwnerKeys(ConversationItem conversation) async {
    if (conversation.type != 'group') return;
    final me = getCurrentUser();
    if (me == null || !conversation.isOwner(me.id)) return;

    var conv = conversation;
    if (conv.members.isEmpty) {
      conv = await refreshConversation(conversation);
    }

    try {
      final bundles = await conversations.fetchKeyBundles(conv.id);
      final epochs = <int>{conv.epoch};
      for (final b in bundles) {
        epochs.add(b.epoch);
      }
      for (var e = 0; e <= conv.epoch; e++) {
        epochs.add(e);
      }
      await ensureKeys(conv, epochs: epochs.toList());
    } catch (_) {
      await ensureKeys(conv);
    }
  }

  /// 建群 / 加人 / 踢人后：生成 GMK 并上传 welcome 包（触发服务端 gmk_updated）。
  Future<void> publishEpochKeys(
    ConversationItem conversation,
    Uint8List gmk,
  ) async {
    var conv = await refreshConversation(conversation);
    final uploads = <Map<String, dynamic>>[];
    for (final member in conv.members) {
      if (!canUseE2EEWithPeer(member.identityPublicKey)) continue;
      final cipher = await crypto().buildGroupWelcome(
        recipient: member,
        conversationId: conv.id,
        epoch: conv.epoch,
        gmk: gmk,
      );
      uploads.add({
        'epoch': conv.epoch,
        'recipient_user_id': member.userId,
        'ciphertext': cipher,
      });
    }
    if (uploads.isEmpty) return;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await conversations.uploadKeyBundles(conv.id, uploads);
        return;
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  Future<void> onIdentityRotated() async {
    await _redistributeOwned();
    await _refetchMember();
  }

  void syncAllCachedInBackground(Iterable<ConversationItem> conversations) {
    final me = getCurrentUser();
    if (me == null) return;
    for (final conv in conversations) {
      if (conv.type != 'group') continue;
      if (conv.isOwner(me.id)) {
        unawaited(ensureOwnerKeys(conv));
      } else {
        unawaited(ensureKeys(conv));
      }
    }
  }

  Future<void> _ensureEpoch(
    ConversationItem conv,
    int epoch, {
    required bool waitForRelay,
  }) async {
    final me = getCurrentUser();
    if (me == null) return;

    final dedupeKey = '${conv.id}:$epoch';
    if (_inFlight.containsKey(dedupeKey)) {
      await _inFlight[dedupeKey];
      return;
    }

    final task = _ensureEpochImpl(conv, epoch, waitForRelay: waitForRelay);
    _inFlight[dedupeKey] = task;
    try {
      await task;
    } finally {
      _inFlight.remove(dedupeKey);
    }
  }

  Future<void> _ensureEpochImpl(
    ConversationItem conv,
    int epoch, {
    required bool waitForRelay,
  }) async {
    final me = getCurrentUser();
    if (me == null) return;

    if (conv.isOwner(me.id)) {
      await _ensureOwnerEpoch(conv, epoch);
      return;
    }

    conv = await refreshConversation(conv);
    if (!await hasGmk(conv.id, epoch)) {
      await _fetchFromServer(conv, epoch);
    }
    if (!await hasGmk(conv.id, epoch)) {
      if (waitForRelay) {
        await _requestViaWs(conv.id, [epoch]);
      } else {
        unawaited(_requestViaWs(conv.id, [epoch]));
      }
    }
  }

  Future<void> _ensureOwnerEpoch(ConversationItem conv, int epoch) async {
    final me = getCurrentUser();
    if (me == null || !conv.isOwner(me.id)) return;

    if (await hasGmk(conv.id, epoch)) {
      return;
    }
    if (await _restoreOwnerSelfBundle(conv, epoch)) {
      conv = await refreshConversation(conv);
      await _backfillBundles(conv, {epoch});
      return;
    }
    conv = await refreshConversation(conv);
    final gmk = await crypto().initGroupEpoch(conv.id, epoch);
    await publishEpochKeys(conv, gmk);
  }

  Future<void> _redistributeOwned() async {
    final me = getCurrentUser();
    if (me == null) return;
    List<ConversationItem> groups;
    try {
      groups = (await conversations.listConversations())
          .where((c) => c.type == 'group' && c.isOwner(me.id))
          .toList();
    } catch (_) {
      return;
    }
    for (final conv in groups) {
      cacheConversation(conv);
      final raw = await storage.readGroupGmk(me.id, conv.id, conv.epoch);
      final Uint8List gmk;
      if (raw != null && raw.length == 32) {
        gmk = Uint8List.fromList(raw);
      } else {
        gmk = await crypto().initGroupEpoch(conv.id, conv.epoch);
      }
      await publishEpochKeys(conv, gmk);
    }
  }

  Future<void> _refetchMember() async {
    final me = getCurrentUser();
    if (me == null) return;
    List<ConversationItem> groups;
    try {
      groups = (await conversations.listConversations())
          .where((c) => c.type == 'group' && !c.isOwner(me.id))
          .toList();
    } catch (_) {
      return;
    }
    for (final conv in groups) {
      cacheConversation(conv);
      await storage.clearGroupGmk(me.id, conv.id, conv.epoch);
      await ensureKeys(conv, epochs: [conv.epoch], waitForRelay: true);
    }
  }

  Future<bool> _restoreOwnerSelfBundle(
    ConversationItem conv,
    int epoch,
  ) async {
    final me = getCurrentUser();
    if (me == null || !conv.isOwner(me.id)) return false;

    ConversationMember? owner;
    for (final m in conv.members) {
      if (m.userId == me.id) {
        owner = m;
        break;
      }
    }
    if (owner == null || !canUseE2EEWithPeer(owner.identityPublicKey)) {
      return false;
    }

    try {
      final bundles = await conversations.fetchKeyBundles(
        conv.id,
        epochs: [epoch],
      );
      for (final bundle in bundles) {
        if (bundle.epoch != epoch || bundle.senderId != me.id) continue;
        if (await hasGmk(conv.id, epoch)) return true;
        try {
          final stored = await crypto().absorbGroupWelcome(
            senderUserId: me.id,
            senderPublicKeyBase64: owner.identityPublicKey,
            ciphertext: bundle.ciphertext,
          );
          _notifyReady(stored.conversationId, stored.epoch);
        } catch (_) {}
      }
    } catch (_) {}
    return hasGmk(conv.id, epoch);
  }

  Future<bool> _fetchFromServer(ConversationItem conv, int epoch) async {
    final me = getCurrentUser();
    if (me == null) return false;

    try {
      final bundles = await conversations.fetchKeyBundles(
        conv.id,
        epochs: [epoch],
      );
      for (final bundle in bundles) {
        if (bundle.epoch != epoch) continue;

        ConversationMember? sender;
        for (final m in conv.members) {
          if (m.userId == bundle.senderId) {
            sender = m;
            break;
          }
        }
        if (sender == null || !canUseE2EEWithPeer(sender.identityPublicKey)) {
          continue;
        }

        try {
          final stored = await crypto().absorbGroupWelcome(
            senderUserId: sender.userId,
            senderPublicKeyBase64: sender.identityPublicKey,
            ciphertext: bundle.ciphertext,
          );
          _notifyReady(stored.conversationId, stored.epoch);
        } catch (_) {}
      }
    } catch (_) {}
    return hasGmk(conv.id, epoch);
  }

  Future<void> _backfillBundles(
    ConversationItem conv,
    Set<int> epochs,
  ) async {
    final me = getCurrentUser();
    if (me == null || !conv.isOwner(me.id)) return;

    conv = await refreshConversation(conv);
    final uploads = <Map<String, dynamic>>[];
    for (final epoch in epochs) {
      final raw = await storage.readGroupGmk(me.id, conv.id, epoch);
      if (raw == null || raw.length != 32) continue;
      final gmk = Uint8List.fromList(raw);

      for (final member in conv.members) {
        if (!canUseE2EEWithPeer(member.identityPublicKey)) continue;
        try {
          final cipher = await crypto().buildGroupWelcome(
            recipient: member,
            conversationId: conv.id,
            epoch: epoch,
            gmk: gmk,
          );
          uploads.add({
            'epoch': epoch,
            'recipient_user_id': member.userId,
            'ciphertext': cipher,
          });
        } catch (_) {}
      }
    }
    if (uploads.isEmpty) return;
    try {
      await conversations.uploadKeyBundles(conv.id, uploads);
    } catch (_) {}
  }

  Future<void> _requestViaWs(String conversationId, List<int> epochs) async {
    if (!ws.isConnected || epochs.isEmpty) return;

    final missing = <int>[];
    for (final epoch in epochs) {
      if (!await hasGmk(conversationId, epoch)) missing.add(epoch);
    }
    if (missing.isEmpty) return;

    final waiters = <({int epoch, Completer<void> completer})>[];
    for (final epoch in missing) {
      final key = '$conversationId:$epoch';
      final completer = Completer<void>();
      _gmkWaiters.putIfAbsent(key, () => []).add(completer);
      waiters.add((epoch: epoch, completer: completer));
    }
    ws.sendGmkRequest(conversationId: conversationId, epochs: missing);

    for (final w in waiters) {
      try {
        await w.completer.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        final key = '$conversationId:${w.epoch}';
        _gmkWaiters[key]?.remove(w.completer);
        if (_gmkWaiters[key]?.isEmpty ?? false) {
          _gmkWaiters.remove(key);
        }
      }
    }
  }

  void _notifyReady(String conversationId, int epoch) {
    final key = '$conversationId:$epoch';
    final waiters = _gmkWaiters.remove(key);
    if (waiters != null) {
      for (final c in waiters) {
        if (!c.isCompleted) c.complete();
      }
    }
    if (getOpenConversationId() == conversationId &&
        !_readyController.isClosed) {
      _readyController.add(conversationId);
    }
  }

  Future<ConversationItem> _resolveConversation(String conversationId) async {
    final cached = getCachedConversation(conversationId);
    return refreshConversation(
      cached ??
          ConversationItem(
            id: conversationId,
            type: 'group',
            members: [],
          ),
    );
  }

  Future<void> _onEpochUpdated(EpochUpdatedFrame frame) async {
    final me = getCurrentUser();
    if (me == null) return;

    var conv = getCachedConversation(frame.conversationId);
    if (conv != null) {
      conv = conv.copyWith(epoch: frame.epoch);
      cacheConversation(conv);
    } else {
      conv = ConversationItem(
        id: frame.conversationId,
        type: 'group',
        members: [],
        epoch: frame.epoch,
      );
      cacheConversation(conv);
    }

    if (!conv.isOwner(me.id)) {
      unawaited(ensureKeys(conv, epochs: [frame.epoch]));
      return;
    }

    final existing =
        await storage.readGroupGmk(me.id, conv.id, frame.epoch);
    if (existing != null) return;

    if (await _restoreOwnerSelfBundle(conv, frame.epoch)) {
      await _backfillBundles(conv, {frame.epoch});
      return;
    }

    try {
      final gmk = await crypto().rotateGroupEpoch(conv.id, frame.epoch);
      await publishEpochKeys(conv, gmk);
    } catch (_) {}
  }

  Future<void> _onGmkUpdated(GmkUpdatedFrame frame) async {
    final me = getCurrentUser();
    if (me == null) return;

    final conv = await _resolveConversation(frame.conversationId);
    if (conv.isOwner(me.id)) return;

    final missing = <int>[];
    for (final epoch in frame.epochs) {
      if (!await hasGmk(frame.conversationId, epoch)) {
        missing.add(epoch);
      }
    }
    if (missing.isEmpty) return;

    var resolved = conv;
    for (final epoch in missing) {
      if (await _fetchFromServer(resolved, epoch)) continue;
      resolved = await _resolveConversation(frame.conversationId);
    }

    final stillMissing = <int>[];
    for (final epoch in missing) {
      if (!await hasGmk(frame.conversationId, epoch)) {
        stillMissing.add(epoch);
      }
    }
    if (stillMissing.isNotEmpty) {
      await _requestViaWs(frame.conversationId, stillMissing);
    }
  }

  Future<void> _onKeyRelay(KeyRelayFrame frame) async {
    final me = getCurrentUser();
    if (me == null || frame.targetUserId != me.id) return;

    final conv = await _resolveConversation(frame.conversationId);
    ConversationMember? sender;
    for (final m in conv.members) {
      if (m.userId == frame.fromUserId) {
        sender = m;
        break;
      }
    }
    if (sender == null || !canUseE2EEWithPeer(sender.identityPublicKey)) {
      return;
    }

    try {
      final stored = await crypto().absorbGroupWelcome(
        senderUserId: sender.userId,
        senderPublicKeyBase64: sender.identityPublicKey,
        ciphertext: frame.ciphertext,
      );
      _notifyReady(stored.conversationId, stored.epoch);
    } catch (_) {}
  }

  Future<void> _onGmkRequest(GmkRequestFrame frame) async {
    final me = getCurrentUser();
    if (me == null) return;

    final conv = await _resolveConversation(frame.conversationId);

    ConversationMember? requester;
    for (final m in conv.members) {
      if (m.userId == frame.requesterUserId) {
        requester = m;
        break;
      }
    }
    if (requester == null || !canUseE2EEWithPeer(requester.identityPublicKey)) {
      return;
    }

    for (final epoch in frame.epochs) {
      final raw = await storage.readGroupGmk(me.id, conv.id, epoch);
      if (raw == null || raw.length != 32) continue;
      try {
        final cipher = await crypto().buildGroupWelcome(
          recipient: requester,
          conversationId: conv.id,
          epoch: epoch,
          gmk: Uint8List.fromList(raw),
        );
        ws.sendKeyRelay(
          conversationId: conv.id,
          targetUserId: requester.userId,
          ciphertext: cipher,
        );
        try {
          await conversations.uploadKeyBundles(conv.id, [
            {
              'epoch': epoch,
              'recipient_user_id': requester.userId,
              'ciphertext': cipher,
            },
          ]);
        } catch (_) {}
      } catch (_) {}
    }
  }
}
