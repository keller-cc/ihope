import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import 'identity.dart';
import 'message_codec.dart';
import 'e2ee_exception.dart';

/// 封装单聊 E2EE：加密发送、解密展示。
class ChatCrypto {
  ChatCrypto({required MessageCodec codec, required this.myUserId})
      : _codec = codec;

  final MessageCodec _codec;
  final String myUserId;

  bool get enabled => myUserId.isNotEmpty;

  Future<String> encryptOutgoing(
    ConversationItem conversation,
    String plaintext,
  ) async {
    if (conversation.type != 'private') {
      throw E2eeException('当前仅支持单聊端到端加密');
    }
    final peer = _peer(conversation);
    if (peer == null) {
      throw E2eeException('找不到聊天对象');
    }
    if (peer.identityPublicKey.isEmpty ||
        !canUseE2EEWithPeer(peer.identityPublicKey)) {
      throw E2eeException('对方尚未配置加密密钥，请让对方重新登录后再试');
    }
    return _codec.encrypt(
      peerUserId: peer.userId,
      peerPublicKeyBase64: peer.identityPublicKey,
      plaintext: plaintext,
    );
  }

  Future<String> decryptIncoming(
    ConversationItem conversation,
    String payload,
  ) async {
    if (!_codec.isEncrypted(payload)) return payload;
    final peer = _peer(conversation);
    if (peer == null) return '[无法解密]';
    if (!canUseE2EEWithPeer(peer.identityPublicKey)) {
      return '[无法解密：对方未配置加密密钥]';
    }
    return _codec.decrypt(
      peerUserId: peer.userId,
      peerPublicKeyBase64: peer.identityPublicKey,
      payload: payload,
    );
  }

  Future<ChatMessage> decryptMessage(
    ConversationItem conversation,
    ChatMessage message,
  ) async {
    final text = await decryptIncoming(conversation, message.ciphertext);
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
  required Future<Uint8List?> Function() readIdentitySeed,
  required Future<void> Function(Uint8List seed) writeIdentitySeed,
  required Future<List<int>?> Function(String peerUserId) readSession,
  required Future<void> Function(String peerUserId, List<int> keyBytes)
      writeSession,
}) {
  final identity = IdentityKeyStore(readIdentitySeed, writeIdentitySeed);
  final codec = MessageCodec(
    loadIdentity: identity.loadOrCreate,
    readSession: readSession,
    writeSession: writeSession,
  );
  return ChatCrypto(codec: codec, myUserId: myUserId);
}

Future<String> identityPublicKeyForRegister({
  required Future<Uint8List?> Function() readIdentitySeed,
  required Future<void> Function(Uint8List seed) writeIdentitySeed,
}) {
  final store = IdentityKeyStore(readIdentitySeed, writeIdentitySeed);
  return store.publicKeyBase64();
}
