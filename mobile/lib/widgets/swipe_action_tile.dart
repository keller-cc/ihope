import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 左滑露出操作气泡（置顶 → 已读 → 删除 依次露出）。
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

class _SwipeActionTileState extends State<SwipeActionTile> {
  double _offset = 0;
  static const _bubbleWidth = 76.0;
  static const _bubbleTop = 10.0;

  /// 右端先露出：actions 中靠前项在左侧，靠后项贴会话行右缘。
  double get _maxOffset => widget.actions.length * _bubbleWidth;

  bool get _isOpen => _offset <= -_bubbleWidth * 0.5;

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

  Widget _buildBubble(SwipeAction action) {
    return SizedBox(
      width: _bubbleWidth,
      child: Center(
        child: Material(
          color: action.color,
          elevation: 2,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _runAction(action),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.icon, color: Colors.white, size: 18),
                  const SizedBox(height: 2),
                  Text(
                    action.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
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
            top: _bubbleTop,
            width: _maxOffset,
            child: Row(
              children: widget.actions.map(_buildBubble).toList(),
            ),
          ),
          Transform.translate(
            offset: Offset(_offset, 0),
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
              child: GestureDetector(
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                onTap: _isOpen ? _close : null,
                behavior: HitTestBehavior.opaque,
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
