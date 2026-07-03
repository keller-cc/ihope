enum MessageSendStatus {
  sent,
  sending,
  failed,
}

class ChatMessage {
  /// 解密完成前 UI 占位，不可写入持久化缓存。
  static const decryptPlaceholder = '…';

  /// 本机乐观发送中的消息 ID 前缀（不入持久化缓存）。
  static const localIdPrefix = 'local:';

  static bool isDecryptPlaceholder(String? plaintext) =>
      plaintext == decryptPlaceholder;

  static bool isDecryptFailure(String? plaintext) =>
      plaintext != null && plaintext.startsWith('[无法解密');

  static bool isLocalId(String id) => id.startsWith(localIdPrefix);

  static String newLocalId() =>
      '$localIdPrefix${DateTime.now().microsecondsSinceEpoch}';

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.ciphertext,
    required this.createdAt,
    this.epoch = 0,
    this.plaintext,
    this.fileId,
    this.sendStatus = MessageSendStatus.sent,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String ciphertext;
  final DateTime createdAt;
  final int epoch;
  final String? plaintext;
  final String? fileId;
  final MessageSendStatus sendStatus;

  bool get isLocalOutgoing => isLocalId(id);

  bool get isPendingOutgoing =>
      isLocalOutgoing && sendStatus != MessageSendStatus.sent;

  /// 可写入消息缓存（已送达的服务端消息）。
  bool get isCacheable => !isLocalOutgoing && sendStatus == MessageSendStatus.sent;

  String get displayText => plaintext ?? ciphertext;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: (json['conversation_id'] as String?) ?? '',
      senderId: json['sender_id'] as String,
      type: json['type'] as String? ?? 'text',
      ciphertext: json['ciphertext'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      epoch: json['epoch'] as int? ?? 0,
      plaintext: json['plaintext'] as String?,
      fileId: json['file_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': type,
        'ciphertext': ciphertext,
        'created_at': createdAt.toUtc().toIso8601String(),
        'epoch': epoch,
        if (plaintext != null) 'plaintext': plaintext,
        if (fileId != null) 'file_id': fileId,
      };

  ChatMessage copyWith({
    String? id,
    String? plaintext,
    String? fileId,
    MessageSendStatus? sendStatus,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      type: type,
      ciphertext: ciphertext,
      createdAt: createdAt,
      epoch: epoch,
      plaintext: plaintext ?? this.plaintext,
      fileId: fileId ?? this.fileId,
      sendStatus: sendStatus ?? this.sendStatus,
    );
  }

  /// 持久化缓存用：去掉本地明文，保留密文供下次解密。
  ChatMessage get forCacheWithoutPlaintext => ChatMessage(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        ciphertext: ciphertext,
        createdAt: createdAt,
        epoch: epoch,
        fileId: fileId,
      );
}
