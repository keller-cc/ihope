import 'package:flutter/material.dart';

/// 群成员头衔标签（如「群主」；后续可扩展自定义头衔）。
class MemberTitleBadge extends StatelessWidget {
  const MemberTitleBadge({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
