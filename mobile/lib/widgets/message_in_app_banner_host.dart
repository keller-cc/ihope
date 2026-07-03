import 'dart:async';

import 'package:flutter/material.dart';

import '../services/message_notification_coordinator.dart';

/// 应用内顶部消息横幅（QQ/微信风格，App 在前台且未打开该会话时）。
class MessageInAppBannerHost extends StatefulWidget {
  const MessageInAppBannerHost({
    super.key,
    required this.stream,
    required this.onTapConversation,
    required this.child,
  });

  final Stream<InAppMessageBannerEvent> stream;
  final void Function(String conversationId) onTapConversation;
  final Widget child;

  @override
  State<MessageInAppBannerHost> createState() => _MessageInAppBannerHostState();
}

class _MessageInAppBannerHostState extends State<MessageInAppBannerHost> {
  StreamSubscription<InAppMessageBannerEvent>? _sub;
  InAppMessageBannerEvent? _event;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _sub = widget.stream.listen(_show);
  }

  @override
  void didUpdateWidget(MessageInAppBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _sub?.cancel();
      _sub = widget.stream.listen(_show);
    }
  }

  void _show(InAppMessageBannerEvent event) {
    _dismissTimer?.cancel();
    setState(() => _event = event);
    _dismissTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _event = null);
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _event;
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        widget.child,
        if (event != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    setState(() => _event = null);
                    widget.onTapConversation(event.conversationId);
                  },
                  child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notifications_active_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (event.count > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '+${event.count - 1}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onError,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
