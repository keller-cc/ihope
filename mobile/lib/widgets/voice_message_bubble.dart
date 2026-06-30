import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 协调聊天内语音播放：同时只播一条。
class VoicePlaybackHub {
  VoicePlaybackHub._();

  static String? _activeId;
  static VoidCallback? _stopActive;

  static void claim(String messageId, VoidCallback stop) {
    if (_activeId != null && _activeId != messageId) {
      _stopActive?.call();
    }
    _activeId = messageId;
    _stopActive = stop;
  }

  static void release(String messageId) {
    if (_activeId == messageId) {
      _activeId = null;
      _stopActive = null;
    }
  }
}

/// QQ 风格语音条：播放/暂停按钮 + 波形条 + 时长。
class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.messageId,
    required this.mine,
    required this.totalSeconds,
    required this.playing,
    required this.positionMs,
    required this.onTap,
  });

  final String messageId;
  final bool mine;
  final int totalSeconds;
  final bool playing;
  final int positionMs;
  final VoidCallback onTap;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _syncWaveAnimation();
  }

  @override
  void didUpdateWidget(VoiceMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWaveAnimation();
  }

  void _syncWaveAnimation() {
    if (widget.playing) {
      if (!_waveController.isAnimating) _waveController.repeat();
    } else {
      _waveController.stop();
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  int get _displaySeconds {
    if (widget.positionMs > 0) {
      final totalMs = widget.totalSeconds * 1000;
      final remaining = ((totalMs - widget.positionMs) / 1000).ceil();
      return math.max(1, remaining);
    }
    return widget.totalSeconds;
  }

  @override
  Widget build(BuildContext context) {
    const minW = 96.0;
    const maxW = 240.0;
    final width =
        minW + (maxW - minW) * (widget.totalSeconds.clamp(1, 60) / 60.0);

    final color = DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;

    final playButton = _PlayPauseButton(playing: widget.playing, color: color);
    final duration = _DurationLabel(
      seconds: _displaySeconds,
      playing: widget.playing,
    );
    final waves = _QQWaveBars(
      playing: widget.playing,
      animation: _waveController,
      color: color,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(4),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: SizedBox(
          width: width,
          height: 40,
          child: Row(
            children: widget.mine
                ? [
                    playButton,
                    const SizedBox(width: 4),
                    Expanded(child: waves),
                    const SizedBox(width: 6),
                    duration,
                  ]
                : [
                    duration,
                    const SizedBox(width: 6),
                    Expanded(child: waves),
                    const SizedBox(width: 4),
                    playButton,
                  ],
          ),
        ),
      ),
    );
  }
}

/// QQ 风格圆形播放/暂停按钮。
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? '暂停' : '播放',
      child: SizedBox(
        width: 28,
        height: 28,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: child,
          ),
          child: playing
              ? Icon(
                  Icons.pause_rounded,
                  key: const ValueKey('pause'),
                  size: 26,
                  color: color,
                )
              : Icon(
                  Icons.play_arrow_rounded,
                  key: const ValueKey('play'),
                  size: 28,
                  color: color,
                ),
        ),
      ),
    );
  }
}

class _DurationLabel extends StatelessWidget {
  const _DurationLabel({required this.seconds, required this.playing});

  final int seconds;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$seconds″',
      style: TextStyle(
        fontSize: 14,
        fontWeight: playing ? FontWeight.w600 : FontWeight.w500,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// QQ 风格波形条（播放时跳动）。
class _QQWaveBars extends StatelessWidget {
  const _QQWaveBars({
    required this.playing,
    required this.animation,
    required this.color,
  });

  final bool playing;
  final Animation<double> animation;
  final Color color;

  static const _barCount = 4;
  static const _phases = [0.0, 0.25, 0.5, 0.75];
  static const _idleHeights = [4.0, 7.0, 5.0, 8.0];
  static const _peakHeights = [10.0, 16.0, 12.0, 18.0];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: playing
          ? AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                return _barRow(
                  heights: List.generate(_barCount, (i) {
                    final t = (animation.value + _phases[i]) % 1.0;
                    final factor = 0.45 + 0.55 * math.sin(t * math.pi);
                    return _idleHeights[i] +
                        (_peakHeights[i] - _idleHeights[i]) * factor;
                  }),
                );
              },
            )
          : _barRow(heights: _idleHeights),
    );
  }

  Widget _barRow({required List<double> heights}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < heights.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 3,
            height: heights[i],
            decoration: BoxDecoration(
              color: color.withValues(alpha: playing ? 0.95 : 0.55),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ],
    );
  }
}
