import 'package:flutter/material.dart';

/// 本机与服务器的实时推送通道（不是对方是否在线）。
class RealtimeIndicator extends StatelessWidget {
  const RealtimeIndicator({
    super.key,
    required this.connected,
    this.onReconnect,
  });

  final bool connected;
  final VoidCallback? onReconnect;

  static const _connectedColor = Color(0xFF2E7D32);
  static const _disconnectedColor = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final color = connected ? _connectedColor : _disconnectedColor;
    final label = connected ? '推送中' : '未连接';

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            connected ? label : '$label · 点重连',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: connected
          ? '本机已连上服务器，新消息会自动推送（不代表对方在线）'
          : '本机未连上服务器；下拉刷新或点击此处重连',
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: connected
            ? child
            : InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onReconnect,
                child: child,
              ),
      ),
    );
  }
}
