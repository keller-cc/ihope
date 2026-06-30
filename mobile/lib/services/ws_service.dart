import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';
import '../models/message.dart';

/// 全局 WebSocket：登录后保持连接，断线自动重连。
class WsService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  String? _accessToken;
  bool _manualClose = false;
  int _reconnectAttempt = 0;

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _connected = false;

  Stream<ChatMessage> get onMessage => _messageController.stream;
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  bool get isConnected => _connected;

  Future<void> connect(String accessToken) async {
    _accessToken = accessToken;
    _manualClose = false;
    _reconnectAttempt = 0;
    _cancelReconnect();
    await _openChannel();
  }

  /// 手动触发重连（如下拉刷新）。
  Future<void> reconnect([String? accessToken]) async {
    if (accessToken != null && accessToken.isNotEmpty) {
      _accessToken = accessToken;
    }
    if (_accessToken == null || _accessToken!.isEmpty) return;
    _manualClose = false;
    _reconnectAttempt = 0;
    _cancelReconnect();
    await _openChannel();
  }

  Future<void> disconnect() async {
    _manualClose = true;
    _accessToken = null;
    _reconnectAttempt = 0;
    _cancelReconnect();
    await _closeChannel();
    _setConnected(false);
  }

  void joinConversation(String conversationId) {
    _send({
      'event': 'join',
      'conversation_id': conversationId,
    });
  }

  Future<void> _openChannel() async {
    final token = _accessToken;
    if (token == null || token.isEmpty || _manualClose) return;

    await _closeChannel();
    _setConnected(false);

    final uri = Uri.parse('${Env.wsBase}/ws?token=$token');
    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(
      (event) {
        if (!_connected) {
          _reconnectAttempt = 0;
          _setConnected(true);
        }
        if (event is! String) return;
        try {
          final frame = jsonDecode(event) as Map<String, dynamic>;
          final msg = parseIncomingMessage(frame);
          if (msg != null) {
            _messageController.add(msg);
          }
        } catch (_) {}
      },
      onError: (_) => _handleDisconnect(),
      onDone: () => _handleDisconnect(),
      cancelOnError: true,
    );
    _setConnected(true);
  }

  Future<void> _closeChannel() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _handleDisconnect() {
    unawaited(_closeChannel());
    _setConnected(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualClose || _accessToken == null) return;

    _cancelReconnect();
    final seconds = min(30, pow(2, _reconnectAttempt).toInt());
    _reconnectAttempt++;

    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (_manualClose || _connected) return;
      unawaited(_openChannel());
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectionController.isClosed) {
      _connectionController.add(value);
    }
  }

  ChatMessage? parseIncomingMessage(Map<String, dynamic> frame) {
    if (frame['event'] != 'message') return null;
    final msg = frame['message'];
    if (msg is! Map<String, dynamic>) return null;
    return ChatMessage.fromJson(msg);
  }
}
