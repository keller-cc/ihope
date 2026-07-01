import 'dart:async';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';

/// 会话消息加载、合并、解密（私聊/群聊共用）。
class ChatThreadLoader {
  ChatThreadLoader({
    required this.auth,
    required this.conversation,
  });

  final AuthService auth;
  final ConversationItem conversation;

  bool get isGroup => conversation.type == 'group';

  static List<ChatMessage> merge(
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

  static List<ChatMessage> upsert(List<ChatMessage> messages, ChatMessage msg) {
    final i = messages.indexWhere((m) => m.id == msg.id);
    if (i < 0) return [...messages, msg];
    return [...messages.sublist(0, i), msg, ...messages.sublist(i + 1)];
  }

  Future<List<ChatMessage>> fetchRemoteMerged(List<ChatMessage> cached) async {
    try {
      final remote = await auth.conversations.listMessages(
        conversation.id,
        limit: 100,
      );
      return cached.isEmpty ? remote : merge(remote, cached);
    } catch (_) {
      return cached;
    }
  }

  Future<void> prepareGroup(List<ChatMessage> msgs) async {
    if (!isGroup || msgs.isEmpty) return;
    unawaited(auth.ensureGroupKeysForMessages(conversation, msgs));
  }

  Future<List<ChatMessage>> resolve({
    List<ChatMessage>? cached,
    required bool fetchRemote,
  }) async {
    var msgs = cached ?? await auth.loadCachedMessages(conversation.id);
    if (fetchRemote) {
      msgs = await fetchRemoteMerged(msgs);
    }
    await prepareGroup(msgs);
    return auth.decryptMessagesLocal(conversation, msgs);
  }

  Future<ChatMessage> materializeIncoming(
    ChatMessage msg,
    List<ChatMessage> current,
  ) async {
    if (msg.type == 'system') {
      return msg.copyWith(plaintext: msg.ciphertext);
    }
    final me = auth.currentUser;
    if (me != null && msg.senderId == me.id) {
      ChatMessage? existing;
      for (final m in current) {
        if (m.id == msg.id) {
          existing = m;
          break;
        }
      }
      var pt = existing?.plaintext;
      if (pt == null ||
          ChatMessage.isDecryptPlaceholder(pt) ||
          ChatMessage.isDecryptFailure(pt)) {
        pt = await auth.cachedPlaintextForMessage(conversation.id, msg.id);
      }
      return msg.copyWith(plaintext: pt ?? ChatMessage.decryptPlaceholder);
    }
    return auth.decryptMessage(conversation, msg);
  }

  Future<void> cacheIfReady(List<ChatMessage> messages) async {
    final cacheable = messages.where((m) => m.isCacheable).toList();
    if (cacheable.isEmpty) return;
    await auth.cacheMessages(conversation.id, cacheable);
  }

  void cacheMessageIfReady(List<ChatMessage> messages, ChatMessage msg) {
    if (!msg.isCacheable) return;
    final pt = msg.plaintext;
    if (pt == null ||
        pt.isEmpty ||
        ChatMessage.isDecryptPlaceholder(pt) ||
        ChatMessage.isDecryptFailure(pt)) {
      return;
    }
    auth.cacheMessages(
      conversation.id,
      messages.where((m) => m.isCacheable).toList(),
    );
  }

  /// 保留本机未送达的乐观消息（刷新/合并历史时不丢失）。
  static List<ChatMessage> preserveLocalOutgoing(
    List<ChatMessage> fresh,
    List<ChatMessage> current,
  ) {
    final pending = current.where((m) => m.isPendingOutgoing).toList();
    if (pending.isEmpty) return fresh;
    var merged = fresh;
    for (final m in pending) {
      merged = upsert(merged, m);
    }
    return merged;
  }
}
