import 'package:flutter/material.dart';

import 'navigation_pop_scope.dart';

/// Opaque [MaterialPageRoute] with controlled back-gesture pop (matches [ChatScreen]).
MaterialPageRoute<T> appPageRoute<T>({
  required WidgetBuilder builder,
}) {
  return MaterialPageRoute<T>(
    builder: (context) => NavigationPopScope(
      child: builder(context),
    ),
  );
}
