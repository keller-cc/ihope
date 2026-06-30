import 'package:flutter/material.dart';

import '../utils/avatar_url.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 22,
    this.badgeCount,
  });

  final String name;
  final String? imageUrl;
  final double radius;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveAvatarUrl(imageUrl);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final avatar = CircleAvatar(
      key: ValueKey(resolved ?? name),
      radius: radius,
      backgroundImage:
          resolved != null ? NetworkImage(resolved) : null,
      child: resolved == null
          ? Text(
              initial,
              style: TextStyle(fontSize: radius * 0.85),
            )
          : null,
    );

    final count = badgeCount ?? 0;
    if (count <= 0) return avatar;

    final label = count > 99 ? '99+' : '$count';
    final wide = count > 99;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          top: -2,
          right: -4,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 4 : 5,
              vertical: 1,
            ),
            constraints: BoxConstraints(
              minWidth: wide ? 22 : 17,
              minHeight: 17,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF8E8E93),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
