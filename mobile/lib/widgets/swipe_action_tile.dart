import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 左滑露出整行等高操作条（置顶 → 已读 → 删除 依次露出）。
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
  static const _actionWidth = 76.0;

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
    final vx = details.velocity.pixelsPerSecond.dx;
    if (vx > 200) {
      setState(() => _offset = 0);
      return;
    }
    if (vx < -200) {
      setState(() => _offset = -_maxOffset);
      return;
    }
    final open = _offset.abs() > _maxOffset * 0.22;
    setState(() => _offset = open ? -_maxOffset : 0);
  }

  Widget _buildAction(SwipeAction action) {
    return SizedBox(
      width: _actionWidth,
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
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
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
    final exposedWidth = _offset.abs();

    return ClipRect(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _maxOffset,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.actions.map(_buildAction).toList(),
                ),
              ),
            ),
          ),
          if (_isOpen && exposedWidth > 0)
            Positioned(
              left: 0,
              width: exposedWidth,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _close,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
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
                child: AbsorbPointer(
                  absorbing: _isOpen,
                  child: Material(
                    color: surface,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
