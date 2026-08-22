import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/message_notification_coordinator.dart';

/// 会话列表顶栏消息提示（QQ 式：仅列表页、窄条、上滑收起）。
class MessageInAppBannerHost extends StatefulWidget {
  const MessageInAppBannerHost({
    super.key,
    required this.stream,
    required this.onTapConversation,
    required this.child,
    this.scopeListenable,
  });

  final Stream<InAppMessageBannerEvent> stream;
  final void Function(String conversationId) onTapConversation;
  final Widget child;
  /// 为 false 时立即收起（进入聊天/设置等子页）。
  final ValueListenable<bool>? scopeListenable;

  @override
  State<MessageInAppBannerHost> createState() => _MessageInAppBannerHostState();
}

class _MessageInAppBannerHostState extends State<MessageInAppBannerHost>
    with SingleTickerProviderStateMixin {
  StreamSubscription<InAppMessageBannerEvent>? _sub;
  InAppMessageBannerEvent? _event;
  Timer? _dismissTimer;
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  double _dragDy = 0;

  static const _showDuration = Duration(milliseconds: 200);
  static const _hideDuration = Duration(milliseconds: 160);
  static const _visibleDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _sub = widget.stream.listen(_show);
    widget.scopeListenable?.addListener(_onScopeChanged);
  }

  @override
  void didUpdateWidget(MessageInAppBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _sub?.cancel();
      _sub = widget.stream.listen(_show);
    }
    if (oldWidget.scopeListenable != widget.scopeListenable) {
      oldWidget.scopeListenable?.removeListener(_onScopeChanged);
      widget.scopeListenable?.addListener(_onScopeChanged);
    }
  }

  void _onScopeChanged() {
    final allowed = widget.scopeListenable?.value ?? true;
    if (!allowed) unawaited(_hide());
  }

  bool get _scopeAllowed => widget.scopeListenable?.value ?? true;

  void _show(InAppMessageBannerEvent event) {
    if (!_scopeAllowed) return;
    _dismissTimer?.cancel();
    _dragDy = 0;
    final wasVisible = _event != null;
    setState(() => _event = event);
    if (!wasVisible) {
      _anim.duration = _showDuration;
      unawaited(_anim.forward(from: 0));
    }
    _dismissTimer = Timer(_visibleDuration, _hide);
  }

  Future<void> _hide() async {
    if (_event == null) return;
    _dismissTimer?.cancel();
    _anim.duration = _hideDuration;
    await _anim.reverse();
    if (mounted) {
      setState(() {
        _event = null;
        _dragDy = 0;
      });
    }
  }

  void _openConversation() {
    final id = _event?.conversationId;
    if (id == null) return;
    unawaited(_hide());
    widget.onTapConversation(id);
  }

  @override
  void dispose() {
    widget.scopeListenable?.removeListener(_onScopeChanged);
    _dismissTimer?.cancel();
    _sub?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    final scheme = Theme.of(context).colorScheme;
    final showBanner = event != null && _scopeAllowed;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _fade,
                  child: Transform.translate(
                    offset: Offset(0, _dragDy),
                    child: GestureDetector(
                      onTap: _openConversation,
                      onVerticalDragUpdate: (d) {
                        if (d.delta.dy < 0) {
                          setState(() => _dragDy += d.delta.dy);
                        }
                      },
                      onVerticalDragEnd: (d) {
                        if (_dragDy < -12 || d.velocity.pixelsPerSecond.dy < -200) {
                          unawaited(_hide());
                        } else {
                          setState(() => _dragDy = 0);
                        }
                      },
                      child: Material(
                        elevation: 4,
                        shadowColor: scheme.shadow.withValues(alpha: 0.18),
                        color: scheme.surfaceContainerHigh
                            .withValues(alpha: 0.96),
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.15),
                                child: Icon(
                                  Icons.person_outline,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _bannerLine(event),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(height: 1.2),
                                ),
                              ),
                              if (event.count > 1)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '${event.count}条',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _bannerLine(InAppMessageBannerEvent event) {
    final body = event.body.trim();
    if (body.isEmpty) return event.title;
    return '${event.title}: $body';
  }
}
