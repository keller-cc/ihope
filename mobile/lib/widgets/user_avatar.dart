import 'package:flutter/material.dart';

import '../utils/avatar_url.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.radius = 22,
  });

  final String name;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final resolved = resolveAvatarUrl(imageUrl);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return CircleAvatar(
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
  }
}
