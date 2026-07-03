import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/auth_service.dart';
import '../services/device_link_service.dart';
import '../widgets/app_page_route.dart';
import '../widgets/auth_form.dart';

/// 多设备链接入口：展示二维码 / 扫描其它设备。
class DeviceLinkScreen extends StatelessWidget {
  const DeviceLinkScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('链接设备')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '将本账号的加密密钥同步到另一台设备，同步后可解密历史消息。'
            '链接过程经服务器中转，但密钥包仅扫码双方持有 token 时可解密。',
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_2_outlined),
            title: const Text('在此设备展示二维码'),
            subtitle: const Text('已登录的旧手机 / 平板'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                appPageRoute(
                  builder: (_) => DeviceLinkHostScreen(auth: auth),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.qr_code_scanner_outlined),
            title: const Text('扫描其它设备二维码'),
            subtitle: const Text('新设备需先登录同一账号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final ok = await Navigator.of(context).push<bool>(
                appPageRoute(
                  builder: (_) => DeviceLinkScanScreen(auth: auth),
                ),
              );
              if (ok == true && context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
        ],
      ),
    );
  }
}

class DeviceLinkHostScreen extends StatefulWidget {
  const DeviceLinkHostScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<DeviceLinkHostScreen> createState() => _DeviceLinkHostScreenState();
}

class _DeviceLinkHostScreenState extends State<DeviceLinkHostScreen> {
  DeviceLinkSession? _session;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await widget.auth.deviceLink.startHostSession();
      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('展示链接二维码')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) ...[
            FormErrorText(message: _error!),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _start, child: const Text('重试')),
          ],
          if (session != null) ...[
            Center(
              child: QrImageView(
                data: session.qrPayload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '请在另一台已登录同一账号的设备上打开「扫描其它设备二维码」。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '二维码约 ${session.expiresAt.toLocal()} 前有效，仅可使用一次。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class DeviceLinkScanScreen extends StatefulWidget {
  const DeviceLinkScanScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<DeviceLinkScanScreen> createState() => _DeviceLinkScanScreenState();
}

class _DeviceLinkScanScreenState extends State<DeviceLinkScanScreen> {
  final _manualController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _handled = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _complete(String payload) async {
    if (_busy || _handled) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await widget.auth.deviceLink.completeFromQrPayload(payload);
      await widget.auth.listAllConversations();
      if (!mounted) return;
      _handled = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已同步 $count 项加密密钥，可解密历史消息')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描链接二维码')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                if (_busy || _handled) return;
                for (final code in capture.barcodes) {
                  final raw = code.rawValue;
                  if (raw != null && raw.contains('"token"')) {
                    unawaited(_complete(raw));
                    break;
                  }
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      labelText: '或粘贴二维码 JSON',
                      hintText: '{"v":1,"token":"..."}',
                    ),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () =>
                        _complete(_manualController.text.trim()),
                    child: const Text('确认链接'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  FormErrorText(message: _error!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
