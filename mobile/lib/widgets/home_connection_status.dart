import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// 首页连接状态，格式如「在线-WiFi」「在线-5G」「离线」。
class HomeConnectionStatus extends StatefulWidget {
  const HomeConnectionStatus({
    super.key,
    required this.wsConnected,
    this.onReconnect,
  });

  final bool wsConnected;
  final VoidCallback? onReconnect;

  @override
  State<HomeConnectionStatus> createState() => _HomeConnectionStatusState();
}

class _HomeConnectionStatusState extends State<HomeConnectionStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _results = [ConnectivityResult.none];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() => _results = results);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final results = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _results = results);
  }

  bool get _hasNetwork =>
      _results.any((r) => r != ConnectivityResult.none);

  String get _networkLabel {
    if (_results.contains(ConnectivityResult.wifi)) return 'WiFi';
    if (_results.contains(ConnectivityResult.ethernet)) return '有线';
    if (_results.contains(ConnectivityResult.mobile)) return '5G';
    if (_results.contains(ConnectivityResult.vpn)) return 'VPN';
    return '无网';
  }

  String get _label {
    if (!_hasNetwork) return '离线';
    final ws = widget.wsConnected ? '在线' : '未连接';
    return '$ws-${_networkLabel}';
  }

  Color _color(ColorScheme scheme) {
    if (!_hasNetwork) return scheme.error;
    if (!widget.wsConnected) return scheme.tertiary;
    return const Color(0xFF2E7D32);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    final text = Text(
      _label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
          ),
    );

    if (!widget.wsConnected && widget.onReconnect != null) {
      return InkWell(
        onTap: widget.onReconnect,
        child: text,
      );
    }
    return text;
  }
}
