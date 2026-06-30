class ChatMessage {
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
}
