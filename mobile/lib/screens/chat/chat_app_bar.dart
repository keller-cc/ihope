import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/user.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/user_avatar.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.conversation,
    required this.me,
    required this.isGroup,
    required this.isArchived,
    required this.onTitleTap,
    required this.onMenu,
    this.onAnnouncements,
    this.announcementUnread = false,
  });

  final ConversationItem conversation;
  final User me;
  final bool isGroup;
  final bool isArchived;
  final VoidCallback? onTitleTap;
  final VoidCallback onMenu;
  final VoidCallback? onAnnouncements;
  final bool announcementUnread;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final title = conversation.displayTitle(me.id);
    return AppBar(
      title: GestureDetector(
        onTap: onTitleTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            UserAvatar(
              name: title,
              imageUrl: conversation.displayAvatarUrl(me.id),
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(text: title, style: Theme.of(context).textTheme.titleMedium),
                  if (isGroup && !isArchived)
                    Text(
                      '${conversation.members.length} 人',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (isArchived)
                    Text(
                      '已退出 · 只读',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (isGroup && !isArchived && onAnnouncements != null)
          IconButton(
            tooltip: '群公告',
            onPressed: onAnnouncements,
            icon: Badge(
              isLabelVisible: announcementUnread,
              smallSize: 8,
              child: const Icon(Icons.campaign_outlined),
            ),
          ),
        if (!isArchived)
          IconButton(
            tooltip: '更多',
            icon: const Icon(Icons.menu),
            onPressed: onMenu,
          ),
      ],
    );
  }
}
