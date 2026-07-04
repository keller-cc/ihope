import 'dart:async';

import 'package:flutter/material.dart';

/// 语音录制提示（居中浮层；再次显示会替换上一条，不用底部 SnackBar）。
class VoiceHintToast {
  VoiceHintToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;

  static bool _isVoiceHint(String message) =>
      message == '说话时间太短' ||
      message.startsWith('需要麦克风权限') ||
      message.startsWith('无法开始录音');

  static bool show(BuildContext context, String message) {
    if (!_isVoiceHint(message)) return false;
    hide();
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) return false;

    _entry = OverlayEntry(
      builder: (context) => IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    _timer = Timer(const Duration(milliseconds: 1500), hide);
    return true;
  }

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}
