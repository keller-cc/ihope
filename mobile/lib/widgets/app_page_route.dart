import 'package:flutter/material.dart';

import 'navigation_pop_scope.dart';

/// Opaque [MaterialPageRoute] with optional [NavigationPopScope] (gesture back).
///
/// [ChatScreen] 自带 [PopScope]，须设 [wrapNavigationPopScope: false] 避免嵌套双 pop。
MaterialPageRoute<T> appPageRoute<T>({
  required WidgetBuilder builder,
  bool wrapNavigationPopScope = true,
}) {
  return MaterialPageRoute<T>(
    builder: (context) => wrapNavigationPopScope
        ? NavigationPopScope(child: builder(context))
        : builder(context),
  );
}
