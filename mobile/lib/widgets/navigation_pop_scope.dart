import 'package:flutter/material.dart';

/// Blocks predictive / edge-swipe back from interactively revealing the route
/// below (ghost/double UI). Pops only after the gesture completes.
class NavigationPopScope extends StatefulWidget {
  const NavigationPopScope({
    super.key,
    required this.child,
    this.onPop,
  });

  final Widget child;
  final Future<Object?> Function()? onPop;

  @override
  State<NavigationPopScope> createState() => _NavigationPopScopeState();
}

class _NavigationPopScopeState extends State<NavigationPopScope> {
  bool _popInProgress = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !context.mounted || _popInProgress) return;
        _popInProgress = true;
        Object? popResult = result;
        try {
          if (widget.onPop != null) {
            popResult = await widget.onPop!();
          }
          if (!context.mounted) return;
          Navigator.of(context).pop(popResult);
        } finally {
          _popInProgress = false;
        }
      },
      child: widget.child,
    );
  }
}
