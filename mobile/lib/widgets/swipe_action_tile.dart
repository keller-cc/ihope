import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// 左滑露出操作按钮（纯本地交互，无额外依赖）。
class SwipeActionTile extends StatefulWidget {
  const SwipeActionTile({
    super.key,
    required this.actions,
    required this.child,
    this.onLongPress,
  });

  final List<SwipeAction> actions;
  final Widget child;
  final void Function(LongPressStartDetails details)? onLongPress;

  @override
  State<SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<SwipeActionTile> {
  double _offset = 0;
  static const _actionWidth = 72.0;

  double get _maxOffset => widget.actions.length * _actionWidth;

  bool get _isOpen => _offset <= -_actionWidth * 0.5;

  void _close() {
    if (_offset == 0) return;
    setState(() => _offset = 0);
  }

  void _runAction(SwipeAction action) {
    action.onTap();
    _close();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_maxOffset, 0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final open = _offset.abs() > _maxOffset * 0.35;
    setState(() => _offset = open ? -_maxOffset : 0);
  }

  Widget _buildActionButton(SwipeAction action) {
    return Expanded(
      child: Material(
        color: action.color,
        child: InkWell(
          onTap: () => _runAction(action),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(
                action.label,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return ClipRect(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: _maxOffset,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.actions.map(_buildActionButton).toList(),
            ),
          ),
          GestureDetector(
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onTap: _isOpen ? _close : null,
            behavior: HitTestBehavior.opaque,
            child: RawGestureDetector(
              gestures: {
                if (widget.onLongPress != null)
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          LongPressGestureRecognizer>(
                    () => LongPressGestureRecognizer(),
                    (LongPressGestureRecognizer instance) {
                      instance.onLongPressStart = widget.onLongPress;
                    },
                  ),
              },
              child: Transform.translate(
                offset: Offset(_offset, 0),
                child: Material(
                  color: surface,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
