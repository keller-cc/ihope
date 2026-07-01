import 'package:flutter/material.dart';

import '../models/message.dart';
import '../utils/announcement_payload.dart';

/// 群聊顶部未读公告条（关闭 ≠ 已读）。
class GroupAnnouncementBanner extends StatelessWidget {
  const GroupAnnouncementBanner({
    super.key,
    required this.announcement,
    required this.isUnread,
    required this.onTap,
    this.onDismiss,
  });

  final ChatMessage announcement;
  final bool isUnread;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final payload = AnnouncementPayload.fromMessage(announcement);
    final preview = payload.body.trim();
    final line = preview.length > 48 ? '${preview.substring(0, 48)}…' : preview;

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.campaign, size: 22, color: scheme.primary),
                  if (isUnread)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          payload.displayTitle,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '未读',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onError,
                                    fontSize: 10,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      line.isEmpty ? '（无内容）' : line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
