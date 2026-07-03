import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import '../models/message.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';
import 'notification_preview.dart';

/// 解析第三方推送 data/extras（仅含密文与元数据）。
ChatMessage? chatMessageFromPushData(Map<String, dynamic> data) {
  final convId = data['conversation_id'];
  final ciphertext = data['ciphertext'];
  if (convId is! String ||
      convId.isEmpty ||
      ciphertext is! String ||
      ciphertext.isEmpty) {
    return null;
  }
  final epochRaw = data['epoch'];
  final epoch = switch (epochRaw) {
    int e => e,
    String s => int.tryParse(s) ?? 0,
    _ => 0,
  };
  return ChatMessage(
    id: data['message_id'] is String ? data['message_id'] as String : '',
    conversationId: convId,
    senderId: data['sender_id'] is String ? data['sender_id'] as String : '',
    type: data['type'] is String ? data['type'] as String : 'text',
    ciphertext: ciphertext,
    epoch: epoch,
    createdAt: DateTime.now(),
  );
}

/// 客户端解密后在系统栏展示明文（第三方通道不传明文）。
Future<void> presentRemotePush(
  Map<String, dynamic> data, {
  required LocalNotificationService local,
  AuthService? auth,
}) async {
  final msg = chatMessageFromPushData(data);
  if (msg == null) return;

  final session = auth ?? AuthService();
  if (!await session.restoreLocalSession()) return;

  final me = session.currentUser;
  if (me == null || msg.senderId == me.id) return;
  if (msg.type == 'announcement' || msg.type == 'system') return;
  if (session.isConversationOpen(msg.conversationId)) return;

  try {
    await session.ensureCryptoReady();
  } catch (_) {
    // 密钥未就绪时仍展示类型占位。
  }

  final titleHint =
      data['title_hint'] is String ? data['title_hint'] as String : null;
  final conv = await session.conversationForId(msg.conversationId);
  final title = conv?.displayTitle(me.id) ?? titleHint ?? 'IHope';

  final body = conv != null
      ? await buildNotificationBody(session, conv, msg)
      : notificationTypeFallback(msg.type);

  await session.noteIncomingMessage(msg);
  final badge = session.totalUnreadCount();

  await local.showMessage(
    conversationId: msg.conversationId,
    title: title,
    body: body,
    badgeNumber: badge > 0 ? badge : 1,
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  final local = LocalNotificationService();
  await local.initialize();
  await presentRemotePush(
    Map<String, dynamic>.from(message.data),
    local: local,
  );
}
