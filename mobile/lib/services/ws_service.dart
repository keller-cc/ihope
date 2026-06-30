import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';
import '../models/message.dart';

typedef WsMessageHandler = void Function(Map<String, dynamic> frame);

class WsService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  WsMessageHandler? onFrame;

  bool get isConnected => _channel != null;

  Future<void> connect(String accessToken) async {
    await disconnect();
    final uri = Uri.parse('${Env.wsBase}/ws?token=$accessToken');
    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(
      (event) {
        if (event is! String) return;
        try {
          final frame = jsonDecode(event) as Map<String, dynamic>;
          onFrame?.call(frame);
        } catch (_) {}
      },
      onError: (_) => disconnect(),
      onDone: () => disconnect(),
    );
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void joinConversation(String conversationId) {
    _send({
      'event': 'join',
      'conversation_id': conversationId,
    });
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  ChatMessage? parseIncomingMessage(Map<String, dynamic> frame) {
    if (frame['event'] != 'message') return null;
    final msg = frame['message'];
    if (msg is! Map<String, dynamic>) return null;
    return ChatMessage.fromJson(msg);
  }
}
