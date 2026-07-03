import 'package:flutter/material.dart';

/// Blocks predictive / edge-swipe back from interactively revealing the route
/// below (ghost/double UI). Pops only after the gesture completes.
class NavigationPopScope extends StatelessWidget {
  const NavigationPopScope({
    super.key,
    required this.child,
    this.onPop,
  });

  final Widget child;
  final Future<Object?> Function()? onPop;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !context.mounted) return;
        Object? popResult = result;
        if (onPop != null) {
          popResult = await onPop!();
        }
        if (!context.mounted) return;
        Navigator.of(context).pop(popResult);
      },
      child: child,
    );
  }
}
