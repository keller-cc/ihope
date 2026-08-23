import 'package:flutter/material.dart';

/// 会话行操作：置顶 / 已读 / 删除，连成一条饱满操作栏。
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

  static const bubbleHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: bubbleHeight,
          child: Row(
            children: [
              Expanded(
                child: _Segment(
                  icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  label: isPinned ? '取消置顶' : '置顶',
                  color: Colors.orange,
                  onTap: onPin,
                ),
              ),
              Expanded(
                child: _Segment(
                  icon: Icons.done_all,
                  label: '已读',
                  color: Colors.blue,
                  onTap: onRead,
                ),
              ),
              Expanded(
                child: _Segment(
                  icon: Icons.delete_outline,
                  label: '删除',
                  color: Colors.red,
                  onTap: onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
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
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
