import 'package:flutter/material.dart';

import 'navigation_pop_scope.dart';

/// 从左侧滑入的面板路由（不透明全屏，避免手势返回时透出下层页面）。
PageRoute<T> slideFromLeftRoute<T>({
  required Widget page,
}) {
  return PageRouteBuilder<T>(
    opaque: true,
    barrierDismissible: false,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) =>
        NavigationPopScope(child: page),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
