import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'voice_record_overlay.dart';

/// QQ / 微信风格聊天输入区。
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onVoiceHoldStart,
    required this.onVoiceHoldEnd,
    required this.onImage,
    required this.onFile,
    required this.onEmoji,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final Future<bool> Function() onVoiceHoldStart;
  final Future<void> Function({required bool cancel}) onVoiceHoldEnd;
  final VoidCallback onImage;
  final VoidCallback onFile;
  final VoidCallback onEmoji;

  static const sendWidth = 58.0;
  static const sendHeight = 36.0;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _voiceMode = false;
  bool _moreOpen = false;
  bool _hasText = false;
  bool _voiceHolding = false;

  bool get _textDisabled => widget.sending;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) setState(() => _hasText = next);
  }

  void _toggleVoiceMode() {
    if (_textDisabled || _voiceHolding) return;
    setState(() {
      _voiceMode = !_voiceMode;
      _voiceHolding = false;
      if (_voiceMode) _moreOpen = false;
    });
    if (_voiceMode) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _toggleMorePanel() {
    if (_textDisabled || _voiceHolding) return;
    setState(() {
      _moreOpen = !_moreOpen;
      if (_moreOpen) {
        _voiceMode = false;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _closePanels() {
    if (!_moreOpen) return;
    setState(() => _moreOpen = false);
  }

  void _onPanelAction(VoidCallback action) {
    setState(() => _moreOpen = false);
    action();
  }

  void _onPlaceholder(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label 功能即将上线')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showSend = !_voiceMode && _hasText;
    final compactVoiceRow = _voiceMode && _voiceHolding;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 8, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IgnorePointer(
                      ignoring: compactVoiceRow,
                      child: Opacity(
                        opacity: compactVoiceRow ? 0 : 1,
                        child: _RoundToolButton(
                          icon: _voiceMode
                              ? Icons.keyboard_outlined
                              : Icons.mic_none_outlined,
                          onTap: _textDisabled ? null : _toggleVoiceMode,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _voiceMode
                          ? _HoldToTalkButton(
                              key: const ValueKey('hold_to_talk'),
                              sending: widget.sending,
                              onHoldingChanged: (holding) {
                                setState(() {
                                  _voiceHolding = holding;
                                  if (holding) _moreOpen = false;
                                });
                              },
                              onHoldStart: widget.onVoiceHoldStart,
                              onHoldEnd: widget.onVoiceHoldEnd,
                            )
                          : _TextInput(
                              controller: widget.controller,
                              disabled: _textDisabled,
                              onTap: _closePanels,
                            ),
                    ),
                    if (showSend && !compactVoiceRow) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        width: ChatInputBar.sendWidth,
                        height: ChatInputBar.sendHeight,
                        child: FilledButton(
                          onPressed: _textDisabled ? null : widget.onSend,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            fixedSize: const Size(
                              ChatInputBar.sendWidth,
                              ChatInputBar.sendHeight,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: widget.sending
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : const Text(
                                  '发送',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 2),
                      IgnorePointer(
                        ignoring: compactVoiceRow,
                        child: Opacity(
                          opacity: compactVoiceRow ? 0 : 1,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _RoundToolButton(
                                icon: Icons.emoji_emotions_outlined,
                                onTap: _textDisabled ? null : widget.onEmoji,
                              ),
                              _RoundToolButton(
                                icon: _moreOpen
                                    ? Icons.close
                                    : Icons.add_circle_outline,
                                color: _moreOpen ? scheme.primary : null,
                                onTap: _textDisabled ? null : _toggleMorePanel,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_moreOpen)
                _MorePanel(
                  onImage: () => _onPanelAction(widget.onImage),
                  onFile: () => _onPanelAction(widget.onFile),
                  onPlaceholder: _onPlaceholder,
                ),
              const SizedBox(height: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundToolButton extends StatelessWidget {
  const _RoundToolButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          size: 26,
          color: color ?? scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.disabled,
    required this.onTap,
  });

  final TextEditingController controller;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: controller,
        enabled: !disabled,
        minLines: 1,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        style: const TextStyle(fontSize: 15, height: 1.25),
        onTap: onTap,
        decoration: InputDecoration(
          hintText: '输入消息…',
          hintStyle: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
            fontSize: 15,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
    );
  }
}

class _HoldToTalkButton extends StatefulWidget {
  const _HoldToTalkButton({
    super.key,
    required this.sending,
    required this.onHoldingChanged,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool sending;
  final ValueChanged<bool> onHoldingChanged;
  final Future<bool> Function() onHoldStart;
  final Future<void> Function({required bool cancel}) onHoldEnd;

  @override
  State<_HoldToTalkButton> createState() => _HoldToTalkButtonState();
}

class _HoldToTalkButtonState extends State<_HoldToTalkButton> {
  bool _holding = false;
  bool _willCancel = false;
  Offset? _startPos;
  int? _activePointer;
  OverlayEntry? _overlayEntry;
  Timer? _tickTimer;
  DateTime? _holdStartedAt;
  final _overlayElapsed = ValueNotifier<int>(0);
  final _overlayWillCancel = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _removePointerRoute();
    _stopTick();
    _removeOverlay();
    _overlayElapsed.dispose();
    _overlayWillCancel.dispose();
    super.dispose();
  }

  void _startTick() {
    _stopTick();
    _holdStartedAt = DateTime.now();
    _overlayElapsed.value = 0;
    _tickTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_holding || _holdStartedAt == null) return;
      final ms = DateTime.now().difference(_holdStartedAt!).inMilliseconds;
      // 微信风格：约 0.2s 后从 1″ 起计
      final sec = ms < 200 ? 0 : (ms ~/ 1000) + 1;
      if (sec != _overlayElapsed.value) {
        _overlayElapsed.value = sec;
      }
    });
  }

  void _stopTick() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _holdStartedAt = null;
  }

  void _insertOverlay() {
    if (!mounted) return;
    _removeOverlay();
    _overlayWillCancel.value = _willCancel;
    _overlayElapsed.value = 0;
    _overlayEntry = OverlayEntry(
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([_overlayElapsed, _overlayWillCancel]),
        builder: (context, _) => VoiceRecordOverlay(
          elapsedSec: _overlayElapsed.value,
          willCancel: _overlayWillCancel.value,
        ),
      ),
    );
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    overlay?.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  int? _routePointer;

  void _addPointerRoute() {
    final pointer = _activePointer;
    if (pointer == null) return;
    _routePointer = pointer;
    GestureBinding.instance.pointerRouter.addRoute(pointer, _onGlobalPointer);
  }

  void _removePointerRoute() {
    final pointer = _routePointer;
    if (pointer == null) return;
    GestureBinding.instance.pointerRouter.removeRoute(pointer, _onGlobalPointer);
    _routePointer = null;
  }

  void _onGlobalPointer(PointerEvent event) {
    if (_activePointer == null || event.pointer != _activePointer) return;
    if (event is PointerMoveEvent) {
      _handlePointerMove(event.position);
    } else if (event is PointerUpEvent) {
      _removePointerRoute();
      final cancel = _willCancel;
      _activePointer = null;
      unawaited(_finishHold(cancel: cancel));
    } else if (event is PointerCancelEvent) {
      _removePointerRoute();
      _activePointer = null;
      unawaited(_finishHold(cancel: true));
    }
  }

  void _handlePointerMove(Offset globalPosition) {
    if (!_holding || _startPos == null) return;
    final cancel = globalPosition.dy - _startPos!.dy < -72;
    if (cancel != _willCancel) {
      _willCancel = cancel;
      _overlayWillCancel.value = cancel;
    }
  }

  Future<void> _beginHold() async {
    if (_holding || widget.sending) return;
    if (!mounted) return;
    setState(() {
      _holding = true;
      _willCancel = false;
    });
    widget.onHoldingChanged(true);
    _insertOverlay();
    _startTick();
    HapticFeedback.lightImpact();

    final started = await widget.onHoldStart();
    if (!mounted) {
      unawaited(widget.onHoldEnd(cancel: true));
      return;
    }
    if (!started && _holding) {
      await _finishHold(cancel: true);
    }
  }

  Future<void> _finishHold({required bool cancel}) async {
    if (!_holding) return;
    _removePointerRoute();
    final shouldCancel = cancel || _willCancel;

    _holding = false;
    _willCancel = false;
    _startPos = null;
    _activePointer = null;
    _stopTick();
    _removeOverlay();

    if (mounted) {
      widget.onHoldingChanged(false);
      setState(() => _holding = false);
    }

    unawaited(widget.onHoldEnd(cancel: shouldCancel));
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || widget.sending || _holding) return;
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    _activePointer = event.pointer;
    _startPos = event.position;
    _addPointerRoute();
    unawaited(_beginHold());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _holding
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _holding
                ? scheme.outlineVariant.withValues(alpha: 0.2)
                : scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: _holding
            ? const SizedBox.shrink()
            : Text(
                '按住 说话',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
      ),
    );
  }
}

class _MorePanel extends StatelessWidget {
  const _MorePanel({
    required this.onImage,
    required this.onFile,
    required this.onPlaceholder,
  });

  final VoidCallback onImage;
  final VoidCallback onFile;
  final void Function(String label) onPlaceholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <_PanelItem>[
      _PanelItem(Icons.photo_outlined, '相册', onImage),
      _PanelItem(Icons.photo_camera_outlined, '拍摄', () => onPlaceholder('拍摄')),
      _PanelItem(Icons.videocam_outlined, '视频', () => onPlaceholder('视频')),
      _PanelItem(Icons.folder_outlined, '文件', onFile),
      _PanelItem(Icons.location_on_outlined, '位置', () => onPlaceholder('位置')),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 8,
          crossAxisSpacing: 4,
          childAspectRatio: 0.95,
        ),
        itemBuilder: (context, index) => _PanelTile(item: items[index]),
      ),
    );
  }
}

class _PanelItem {
  const _PanelItem(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _PanelTile extends StatelessWidget {
  const _PanelTile({required this.item});

  final _PanelItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Icon(
                item.icon,
                size: 28,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
