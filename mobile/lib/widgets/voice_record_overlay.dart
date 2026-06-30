import 'package:flutter/material.dart';

/// 微信风格录音蒙版。
class VoiceRecordOverlay extends StatelessWidget {
  const VoiceRecordOverlay({
    super.key,
    required this.elapsedSec,
    required this.willCancel,
  });

  final int elapsedSec;
  final bool willCancel;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: _RecordingBubble(
                  elapsedSec: elapsedSec,
                  willCancel: willCancel,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CancelZoneHint(willCancel: willCancel),
                      if (!willCancel) ...[
                        const SizedBox(height: 20),
                        Text(
                          '松开 发送',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部取消区：默认灰色 X + 上滑提示；进入取消区后变红。
class _CancelZoneHint extends StatelessWidget {
  const _CancelZoneHint({required this.willCancel});

  final bool willCancel;

  @override
  Widget build(BuildContext context) {
    final active = willCancel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: active ? 88 : 72,
          height: active ? 88 : 72,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFFA5151)
                : Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: active
                  ? const Color(0xFFFA5151)
                  : Colors.white.withValues(alpha: 0.35),
              width: active ? 0 : 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.85),
            size: active ? 44 : 36,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          active ? '松开手指，取消发送' : '手指上滑，取消发送',
          style: TextStyle(
            color: Colors.white.withValues(alpha: active ? 1 : 0.82),
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _RecordingBubble extends StatelessWidget {
  const _RecordingBubble({
    required this.elapsedSec,
    required this.willCancel,
  });

  final int elapsedSec;
  final bool willCancel;

  @override
  Widget build(BuildContext context) {
    if (willCancel) {
      return Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF545454),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.mic_none, color: Colors.white54, size: 56),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFF95EC69),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _MicWaveIcon(color: Color(0xFF1A1A1A)),
          const SizedBox(width: 16),
          Text(
            elapsedSec > 0 ? '$elapsedSec″' : '1″',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A1A),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicWaveIcon extends StatelessWidget {
  const _MicWaveIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _bar(10),
        const SizedBox(width: 3),
        _bar(18),
        const SizedBox(width: 3),
        _bar(14),
        const SizedBox(width: 3),
        _bar(22),
      ],
    );
  }

  Widget _bar(double h) {
    return Container(
      width: 4,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
