import 'package:flutter/material.dart';

/// 文本超出宽度时水平滚动；否则静态显示。
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.gap = 32,
  });

  final String text;
  final TextStyle? style;
  final double gap;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _distance = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _stop({bool rebuild = false}) {
    final had = _controller != null;
    _controller?.dispose();
    _controller = null;
    _distance = 0;
    if (rebuild && had && mounted) setState(() {});
  }

  void _start(double textWidth, double viewWidth) {
    if (!mounted) return;
    final distance = textWidth + widget.gap;
    final existing = _controller;
    if (existing != null && (_distance - distance).abs() < 1) {
      if (existing.isAnimating) return;
      existing.repeat();
      return;
    }
    _stop();
    if (!mounted) return;
    _distance = distance;
    final ms = (distance * 28).round().clamp(4000, 14000);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    )..repeat();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth.isInfinite || maxWidth <= 0) {
          return Text(widget.text, style: style, maxLines: 1);
        }

        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        if (painter.width <= maxWidth) {
          if (_controller != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _stop(rebuild: true);
            });
          }
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.clip,
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _start(painter.width, maxWidth);
        });

        if (_controller == null) {
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        final controller = _controller!;
        return ClipRect(
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final offset = -controller.value * _distance;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, style: style, maxLines: 1),
                    SizedBox(width: widget.gap),
                    Text(widget.text, style: style, maxLines: 1),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
