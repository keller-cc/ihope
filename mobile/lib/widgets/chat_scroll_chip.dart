import 'package:flutter/material.dart';

/// QQ 风格右侧浮动条：贴右缘、中部垂直排列。
class ChatScrollChip extends StatelessWidget {
  const ChatScrollChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      color: scheme.surface,
      borderRadius: const BorderRadius.horizontal(
        left: Radius.circular(20),
        right: Radius.zero,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(20),
          right: Radius.zero,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UnreadMessagesDivider extends StatelessWidget {
  const UnreadMessagesDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('以下为新消息', style: style),
          ),
          Expanded(
            child: Divider(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
