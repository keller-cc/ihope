/// 从聊天记录查找返回会话；[messageId] 为空则仅返回会话不定位。
class ChatHistoryJump {
  const ChatHistoryJump({this.messageId});

  final String? messageId;
}
