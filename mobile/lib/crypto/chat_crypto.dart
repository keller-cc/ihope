import 'dart:typed_data';

import '../models/conversation.dart';
import '../models/message.dart';
import 'e2ee_exception.dart';
import 'group_epoch.dart';
import 'identity.dart';
import 'signal/signal_dm_service.dart';

/// 封装单聊（Signal）与群聊（Megolm GMK）。
class ChatCrypto {
  ChatCrypto({
    required SignalDmService signal,
    required GroupCrypto group,
    required this.myUserId,
  })  : _signal = signal,
        _group = group;

  final SignalDmService _signal;
  final GroupCrypto _group;
  final String myUserId;

  SignalDmService get signal => _signal;

  bool get enabled => myUserId.isNotEmpty;

  Future<String> encryptOutgoing(
    ConversationItem conversation,
    String plaintext,
  ) async {
    if (conversation.type == 'group') {
      return _group.encryptGroupMessage(
        conversation.id,
        conversation.epoch,
        plaintext,
      );
    }
    if (conversation.type != 'private') {
      throw E2eeException('不支持的会话类型');
    }
    final peer = _peer(conversation);
    if (peer == null) {
      throw E2eeException('找不到聊天对象');
    }
    if (peer.identityPublicKey.isEmpty ||
        !canUseE2EEWithPeer(peer.identityPublicKey)) {
      throw E2eeException('对方尚未配置加密密钥，请让对方重新登录后再试');
    }
    return _signal.encrypt(peer.userId, plaintext);
  }

  Future<String> decryptIncoming(
    ConversationItem conversation,
    String payload, {
    int? messageEpoch,
  }) async {
    if (conversation.type == 'group') {
      final epoch = messageEpoch ?? conversation.epoch;
      return _group.decryptGroupMessage(conversation.id, epoch, payload);
    }
    if (!_signal.isEncrypted(payload)) return payload;
    final peer = _peer(conversation);
    if (peer == null) return '[无法解密]';
    if (!canUseE2EEWithPeer(peer.identityPublicKey)) {
      return '[无法解密：对方未配置加密密钥]';
    }
    return _signal.decrypt(peer.userId, payload);
  }

  Future<ChatMessage> decryptMessage(
    ConversationItem conversation,
    ChatMessage message,
  ) async {
    if (message.type == 'system') {
      return message.copyWith(plaintext: message.ciphertext);
    }
    final text = await decryptIncoming(
      conversation,
      message.ciphertext,
      messageEpoch: message.epoch,
    );
    return message.copyWith(plaintext: text);
  }

  Future<List<ChatMessage>> decryptMessages(
    ConversationItem conversation,
    List<ChatMessage> messages,
  ) async {
    final out = <ChatMessage>[];
    for (final msg in messages) {
      out.add(await decryptMessage(conversation, msg));
    }
    return out;
  }

  Future<Uint8List> initGroupEpoch(String conversationId, int epoch) {
    return _group.generateAndStoreGmk(conversationId, epoch);
  }

  Future<Uint8List> rotateGroupEpoch(String conversationId, int epoch) {
    return _group.generateAndStoreGmk(conversationId, epoch);
  }

  Future<String> buildGroupWelcome({
    required ConversationMember recipient,
    required String conversationId,
    required int epoch,
    required Uint8List gmk,
  }) {
    return _group.buildWelcomeCiphertext(
      recipientUserId: recipient.userId,
      recipientPublicKeyBase64: recipient.identityPublicKey,
      conversationId: conversationId,
      epoch: epoch,
      gmk: gmk,
    );
  }

  Future<({String conversationId, int epoch})> absorbGroupWelcome({
    required String senderUserId,
    required String senderPublicKeyBase64,
    required String ciphertext,
  }) {
    return _group.absorbWelcome(
      senderUserId: senderUserId,
      senderPublicKeyBase64: senderPublicKeyBase64,
      ciphertext: ciphertext,
    );
  }

  bool isEncryptedPayload(String payload) {
    return _signal.isEncrypted(payload) || _group.isGroupEncrypted(payload);
  }

  ConversationMember? _peer(ConversationItem conversation) {
    if (conversation.type != 'private') return null;
    for (final m in conversation.members) {
      if (m.userId != myUserId) return m;
    }
    return null;
  }
}

ChatCrypto createChatCrypto({
  required String myUserId,
  required SignalDmService signal,
  required Future<List<int>?> Function(String conversationId, int epoch)
      readGroupGmk,
  required Future<void> Function(String conversationId, int epoch, List<int> bytes)
      writeGroupGmk,
}) {
  final group = GroupCrypto(
    store: GroupEpochStore(readGmk: readGroupGmk, writeGmk: writeGroupGmk),
    loadIdentity: signal.groupIdentityKeyPair,
    myUserId: myUserId,
  );
  return ChatCrypto(signal: signal, group: group, myUserId: myUserId);
}
