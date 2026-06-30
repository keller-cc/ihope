class ChatMessage {
  /// 解密完成前 UI 占位，不可写入持久化缓存。
  static const decryptPlaceholder = '…';

  static bool isDecryptPlaceholder(String? plaintext) =>
      plaintext == decryptPlaceholder;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.ciphertext,
    required this.createdAt,
    this.epoch = 0,
    this.plaintext,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String ciphertext;
  final DateTime createdAt;
  final int epoch;
  final String? plaintext;

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
      };

  ChatMessage copyWith({String? plaintext}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: type,
      ciphertext: ciphertext,
      createdAt: createdAt,
      epoch: epoch,
      plaintext: plaintext ?? this.plaintext,
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
      );
}
