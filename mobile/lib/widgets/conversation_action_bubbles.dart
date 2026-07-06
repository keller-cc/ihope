import 'package:flutter/material.dart';

/// 会话行操作：置顶 / 已读 / 删除，气泡横排。
class ConversationActionBubbles extends StatelessWidget {
  const ConversationActionBubbles({
    super.key,
    required this.isPinned,
    required this.onPin,
    required this.onRead,
    required this.onDelete,
  });

  final bool isPinned;
  final VoidCallback onPin;
  final VoidCallback onRead;
  final VoidCallback onDelete;

  static const bubbleHeight = 44.0;
  static const bubbleSpacing = 8.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Bubble(
            icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            label: isPinned ? '取消' : '置顶',
            color: Colors.orange,
            onTap: onPin,
          ),
          const SizedBox(width: bubbleSpacing),
          _Bubble(
            icon: Icons.done_all,
            label: '已读',
            color: Colors.blue,
            onTap: onRead,
          ),
          const SizedBox(width: bubbleSpacing),
          _Bubble(
            icon: Icons.delete_outline,
            label: '删除',
            color: Colors.red,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
