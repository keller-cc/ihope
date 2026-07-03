import '../models/conversation.dart';
import '../models/message.dart';
import 'auth_service.dart';

String notificationTypeFallback(String type) {
  switch (type) {
    case 'image':
      return '[图片]';
    case 'audio':
      return '[语音]';
    case 'file':
      return '[文件]';
    case 'announcement':
      return '[群公告]';
    case 'system':
      return '[系统消息]';
    default:
      return '收到一条新消息';
  }
}

String senderDisplayName(ConversationItem conv, String senderId) {
  for (final m in conv.members) {
    if (m.userId == senderId) return m.username;
  }
  return '?';
}

/// 解密后生成通知正文；失败时返回类型占位，不含密文。
Future<String> buildNotificationBody(
  AuthService auth,
  ConversationItem conv,
  ChatMessage msg,
) async {
  try {
    final preview = await auth.decryptPreview(conv, msg);
    if (preview == ChatMessage.decryptPlaceholder ||
        ChatMessage.isDecryptFailure(preview)) {
      return notificationTypeFallback(msg.type);
    }
    if (conv.type == 'group') {
      final senderName = senderDisplayName(conv, msg.senderId);
      return '$senderName: $preview';
    }
    return preview;
  } catch (_) {
    return notificationTypeFallback(msg.type);
  }
}
