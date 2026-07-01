/// 本机记录的 Megolm epoch 轮换元数据。
class MegolmRotationMeta {
  MegolmRotationMeta({
    required this.messageCount,
    required this.lastRotatedAt,
  });

  final int messageCount;
  final DateTime lastRotatedAt;

  factory MegolmRotationMeta.initial() {
    return MegolmRotationMeta(
      messageCount: 0,
      lastRotatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'message_count': messageCount,
        'last_rotated_at': lastRotatedAt.toUtc().toIso8601String(),
      };

  factory MegolmRotationMeta.fromJson(Map<String, dynamic> json) {
    return MegolmRotationMeta(
      messageCount: json['message_count'] as int? ?? 0,
      lastRotatedAt: DateTime.tryParse(
            json['last_rotated_at'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }
}
