import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../utils/media_local_cache.dart';
import '../../utils/media_payload.dart';

/// 文本/图片/文件/语音发送（私聊/群聊共用）。
class ChatOutgoingController {
  ChatOutgoingController({
    required this.auth,
    required this.conversation,
    required this.onPending,
    required this.onSent,
    required this.onFailed,
    required this.onError,
  });

  final AuthService auth;
  final ConversationItem Function() conversation;
  final void Function(ChatMessage msg) onPending;
  final void Function(String localId, ChatMessage serverMsg) onSent;
  final void Function(String localId, String error) onFailed;
  final void Function(String message) onError;

  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _voiceStartInProgress = false;
  bool _voiceCancelOnStart = false;
  DateTime? _recordStartedAt;
  Timer? _voiceLimitTimer;

  bool get isRecording => _recording || _voiceStartInProgress;

  Future<void> dispose() async {
    _voiceLimitTimer?.cancel();
    if (_recording || _voiceStartInProgress) {
      _voiceCancelOnStart = true;
      await _recorder.stop();
    }
    await _recorder.dispose();
  }

  ChatMessage _buildLocal({
    required String type,
    required String plaintext,
    String? existingId,
  }) {
    final me = auth.currentUser!;
    return ChatMessage(
      id: existingId ?? ChatMessage.newLocalId(),
      conversationId: conversation().id,
      senderId: me.id,
      type: type,
      ciphertext: '',
      createdAt: DateTime.now().toUtc(),
      plaintext: plaintext,
      sendStatus: MessageSendStatus.sending,
    );
  }

  Future<String?> _plaintextForSend(ChatMessage msg) async {
    if (msg.type == 'text') return msg.plaintext;
    final pt = msg.plaintext;
    if (pt == null || pt.isEmpty) return null;
    final inline = MediaPayload.tryParse(pt);
    if (inline != null) return inline.encodePlaintext();
    if (MediaLocalCache.isLocalRef(pt)) {
      final resolved = await MediaLocalCache.resolve(msg.id, pt);
      return resolved?.encodePlaintext();
    }
    return pt;
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final local = _buildLocal(type: 'text', plaintext: trimmed);
    onPending(local);
    try {
      final msg = await auth.sendChatMessage(conversation(), trimmed);
      onSent(local.id, msg);
    } catch (e) {
      onFailed(local.id, e.toString());
    }
  }

  Future<void> resend(ChatMessage msg) async {
    if (!msg.isLocalOutgoing || msg.sendStatus != MessageSendStatus.failed) {
      return;
    }
    final plaintext = await _plaintextForSend(msg);
    if (plaintext == null) {
      onError('无法重发：消息内容已丢失');
      return;
    }
    onPending(msg.copyWith(sendStatus: MessageSendStatus.sending));
    try {
      final server = await auth.sendChatMessage(
        conversation(),
        plaintext,
        type: msg.type,
      );
      onSent(msg.id, server);
    } catch (e) {
      onFailed(msg.id, e.toString());
    }
  }

  Future<void> sendMedia({
    required String type,
    required MediaPayload media,
  }) async {
    final maxBytes = type == 'audio' ? kMaxAudioBytes : kMaxMediaBytes;
    if (media.bytes.length > maxBytes) {
      onError(
        type == 'audio'
            ? '语音过大，请控制在 ${kMaxVoiceDuration.inSeconds} 秒以内'
            : '文件过大，请选择 8MB 以内的内容',
      );
      return;
    }
    final plaintext = media.encodePlaintext();
    final local = _buildLocal(type: type, plaintext: plaintext);
    onPending(local);
    try {
      final msg = await auth.sendChatMessage(
        conversation(),
        plaintext,
        type: type,
      );
      onSent(local.id, msg);
    } catch (e) {
      onFailed(local.id, e.toString());
    }
  }

  Future<void> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (file == null) return;
      final name = file.name.isNotEmpty
          ? file.name
          : source == ImageSource.camera
              ? 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg'
              : 'image.jpg';
      await sendMedia(
        type: 'image',
        media: MediaPayload(
          kind: 'image',
          mime: 'image/jpeg',
          name: name,
          bytes: await file.readAsBytes(),
        ),
      );
    } catch (e) {
      onError(
        source == ImageSource.camera
            ? '无法打开相机，请检查权限设置'
            : '无法选择图片',
      );
    }
  }

  Future<void> captureImage() => pickImage(source: ImageSource.camera);

  Future<void> pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await sendMedia(
      type: 'file',
      media: MediaPayload(
        kind: 'file',
        mime: file.extension != null
            ? 'application/${file.extension}'
            : 'application/octet-stream',
        name: file.name,
        bytes: bytes,
      ),
    );
  }

  Future<bool> startVoiceRecord() async {
    if (_recording || _voiceStartInProgress) return false;
    _voiceStartInProgress = true;
    try {
      if (_voiceCancelOnStart) {
        _voiceCancelOnStart = false;
        return false;
      }
      if (!await _recorder.hasPermission()) {
        onError('需要麦克风权限才能发送语音');
        return false;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      if (_voiceCancelOnStart) {
        _voiceCancelOnStart = false;
        await _recorder.stop();
        return false;
      }
      _recording = true;
      _recordStartedAt = DateTime.now();
      _voiceLimitTimer?.cancel();
      _voiceLimitTimer = Timer(kMaxVoiceDuration, () {
        if (_recording) unawaited(finishVoiceRecord(cancel: false));
      });
      return true;
    } catch (e) {
      onError('无法开始录音：$e');
      return false;
    } finally {
      _voiceStartInProgress = false;
    }
  }

  Future<void> finishVoiceRecord({required bool cancel}) async {
    if (!_recording) {
      if (_voiceStartInProgress) _voiceCancelOnStart = true;
      return;
    }
    _voiceLimitTimer?.cancel();
    final path = await _recorder.stop();
    final started = _recordStartedAt;
    _recording = false;
    _recordStartedAt = null;
    if (cancel || path == null) return;
    final durationMs =
        started == null ? null : DateTime.now().difference(started).inMilliseconds;
    if ((durationMs ?? 0) < 800) {
      onError('说话时间太短');
      return;
    }
    await sendMedia(
      type: 'audio',
      media: MediaPayload(
        kind: 'audio',
        mime: 'audio/m4a',
        name: 'voice.m4a',
        bytes: await File(path).readAsBytes(),
        durationMs: durationMs,
      ),
    );
  }
}
