class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.ciphertext,
    required this.createdAt,
    this.plaintext,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String ciphertext;
  final DateTime createdAt;
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
    );
  }

  ChatMessage copyWith({String? plaintext}) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      type: type,
      ciphertext: ciphertext,
      createdAt: createdAt,
      plaintext: plaintext ?? this.plaintext,
    );
  }
}
