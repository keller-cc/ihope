import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/env.dart';
import '../models/message.dart';

class KeyRelayFrame {
  KeyRelayFrame({
    required this.conversationId,
    required this.fromUserId,
    required this.targetUserId,
    required this.ciphertext,
    this.payloadType = 'welcome_bundle',
  });

  final String conversationId;
  final String fromUserId;
  final String targetUserId;
  final String ciphertext;
  final String payloadType;
}

class GmkRequestFrame {
  GmkRequestFrame({
    required this.conversationId,
    required this.requesterUserId,
    required this.epochs,
  });

  final String conversationId;
  final String requesterUserId;
  final List<int> epochs;
}

class EpochUpdatedFrame {
  EpochUpdatedFrame({
    required this.conversationId,
    required this.epoch,
  });

  final String conversationId;
  final int epoch;
}

class GroupDissolvedFrame {
  GroupDissolvedFrame({
    required this.conversationId,
    required this.groupName,
    required this.dissolvedBy,
  });

  final String conversationId;
  final String groupName;
  final String dissolvedBy;
}

class ConversationAddedFrame {
  ConversationAddedFrame({required this.conversation});

  final Map<String, dynamic> conversation;
}

class ConversationRemovedFrame {
  ConversationRemovedFrame({required this.conversationId});

  final String conversationId;
}

class ConversationUpdatedFrame {
  ConversationUpdatedFrame({required this.conversation});

  final Map<String, dynamic> conversation;
}

/// 全局 WebSocket：登录后保持连接，断线自动重连。
class WsService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  String? _accessToken;
  bool _manualClose = false;
  int _reconnectAttempt = 0;

  /// 重连前获取最新 access token（含 refresh）。
  Future<String?> Function()? resolveToken;

  final _messageController = StreamController<ChatMessage>.broadcast();
  final _keyRelayController = StreamController<KeyRelayFrame>.broadcast();
  final _gmkRequestController = StreamController<GmkRequestFrame>.broadcast();
  final _epochController = StreamController<EpochUpdatedFrame>.broadcast();
  final _groupDissolvedController =
      StreamController<GroupDissolvedFrame>.broadcast();
  final _conversationAddedController =
      StreamController<ConversationAddedFrame>.broadcast();
  final _conversationRemovedController =
      StreamController<ConversationRemovedFrame>.broadcast();
  final _conversationUpdatedController =
      StreamController<ConversationUpdatedFrame>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  bool _connected = false;

  Stream<ChatMessage> get onMessage => _messageController.stream;
  Stream<KeyRelayFrame> get onKeyRelay => _keyRelayController.stream;
  Stream<GmkRequestFrame> get onGmkRequest => _gmkRequestController.stream;
  Stream<EpochUpdatedFrame> get onEpochUpdated => _epochController.stream;
  Stream<GroupDissolvedFrame> get onGroupDissolved =>
      _groupDissolvedController.stream;
  Stream<ConversationAddedFrame> get onConversationAdded =>
      _conversationAddedController.stream;
  Stream<ConversationRemovedFrame> get onConversationRemoved =>
      _conversationRemovedController.stream;
  Stream<ConversationUpdatedFrame> get onConversationUpdated =>
      _conversationUpdatedController.stream;
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

  void sendKeyRelay({
    required String conversationId,
    required String targetUserId,
    required String ciphertext,
    String payloadType = 'welcome_bundle',
  }) {
    _send({
      'event': 'key_relay',
      'conversation_id': conversationId,
      'target_user_id': targetUserId,
      'payload_type': payloadType,
      'ciphertext': ciphertext,
    });
  }

  void sendGmkRequest({
    required String conversationId,
    List<int>? epochs,
    int? epoch,
  }) {
    _send({
      'event': 'gmk_request',
      'conversation_id': conversationId,
      if (epochs != null && epochs.isNotEmpty) 'epochs': epochs,
      if (epoch != null) 'epoch': epoch,
    });
  }

  Future<void> _openChannel() async {
    if (_manualClose) return;

    if (resolveToken != null) {
      final fresh = await resolveToken!();
      if (fresh == null || fresh.isEmpty) {
        _manualClose = true;
        _setConnected(false);
        return;
      }
      _accessToken = fresh;
    }

    final token = _accessToken;
    if (token == null || token.isEmpty) return;

    await _closeChannel();
    _setConnected(false);

    final uri = Uri.parse('${Env.wsBase}/ws?token=$token');
    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (_) {
      _handleDisconnect();
      return;
    }

    _sub = _channel!.stream.listen(
      (event) {
        if (event is! String) return;
        try {
          final frame = jsonDecode(event) as Map<String, dynamic>;
          _dispatchFrame(frame);
        } catch (_) {}
      },
      onError: (_) => _handleDisconnect(),
      onDone: () => _handleDisconnect(),
      cancelOnError: true,
    );
    _reconnectAttempt = 0;
    _setConnected(true);
  }

  void _dispatchFrame(Map<String, dynamic> frame) {
    final event = frame['event'] as String?;
    if (event == 'message') {
      final msg = parseIncomingMessage(frame);
      if (msg != null) {
        _messageController.add(msg);
      }
      return;
    }
    if (event == 'key_relay') {
      final convId = frame['conversation_id'] as String?;
      final from = frame['from_user_id'] as String?;
      final target = frame['target_user_id'] as String?;
      final cipher = frame['ciphertext'] as String?;
      if (convId != null && from != null && target != null && cipher != null) {
        _keyRelayController.add(KeyRelayFrame(
          conversationId: convId,
          fromUserId: from,
          targetUserId: target,
          ciphertext: cipher,
          payloadType: frame['payload_type'] as String? ?? 'welcome_bundle',
        ));
      }
      return;
    }
    if (event == 'gmk_request') {
      final convId = frame['conversation_id'] as String?;
      final requester = frame['requester_user_id'] as String?;
      final epochsRaw = frame['epochs'];
      if (convId != null && requester != null) {
        final epochs = <int>[];
        if (epochsRaw is List) {
          for (final e in epochsRaw) {
            if (e is int) epochs.add(e);
          }
        }
        _gmkRequestController.add(GmkRequestFrame(
          conversationId: convId,
          requesterUserId: requester,
          epochs: epochs,
        ));
      }
      return;
    }
    if (event == 'epoch_updated') {
      final convId = frame['conversation_id'] as String?;
      final epoch = frame['epoch'];
      if (convId != null && epoch is int) {
        _epochController.add(EpochUpdatedFrame(
          conversationId: convId,
          epoch: epoch,
        ));
      }
      return;
    }
    if (event == 'group_dissolved') {
      final convId = frame['conversation_id'] as String?;
      if (convId != null) {
        _groupDissolvedController.add(GroupDissolvedFrame(
          conversationId: convId,
          groupName: frame['group_name'] as String? ?? '',
          dissolvedBy: frame['dissolved_by'] as String? ?? '',
        ));
      }
      return;
    }
    if (event == 'conversation_added') {
      final conv = frame['conversation'];
      if (conv is Map<String, dynamic>) {
        _conversationAddedController.add(
          ConversationAddedFrame(conversation: conv),
        );
      }
      return;
    }
    if (event == 'conversation_removed') {
      final convId = frame['conversation_id'] as String?;
      if (convId != null) {
        _conversationRemovedController.add(
          ConversationRemovedFrame(conversationId: convId),
        );
      }
      return;
    }
    if (event == 'conversation_updated') {
      final conv = frame['conversation'];
      if (conv is Map<String, dynamic>) {
        _conversationUpdatedController.add(
          ConversationUpdatedFrame(conversation: conv),
        );
      }
    }
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

    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (_manualClose || _connected) return;
      await _openChannel();
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
