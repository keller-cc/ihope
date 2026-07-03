import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../widgets/auth_form.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<UserDeviceItem> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.auth.devices.listDevices();
      if (!mounted) return;
      setState(() {
        _devices = items;
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

  Future<void> _kick(UserDeviceItem device) async {
    final isCurrent = device.isCurrent;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCurrent ? '退出本机登录' : '踢下线'),
        content: Text(
          isCurrent
              ? '确定退出本机登录？本地加密密钥会保留，下次登录仍可使用。'
              : '确定让「${device.displayName(widget.auth.storage)}」退出登录？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (isCurrent) {
        await widget.auth.logout();
        if (!mounted) return;
        Navigator.of(context).pop('logout');
        return;
      }
      await widget.auth.devices.kickDevice(device.deviceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已踢下线')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('已登录设备'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '踢下线仅清除该设备的登录会话，不会删除已同步的加密密钥。',
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    FormErrorText(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  if (_devices.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: Text('暂无设备记录')),
                    ),
                  for (final d in _devices)
                    Card(
                      child: ListTile(
                        title: Text(d.displayName(widget.auth.storage)),
                        subtitle: Text(d.subtitle()),
                        trailing: d.isCurrent
                            ? TextButton(
                                onPressed: () => _kick(d),
                                child: const Text('退出登录'),
                              )
                            : (d.hasSession
                                ? TextButton(
                                    onPressed: () => _kick(d),
                                    child: const Text('踢下线'),
                                  )
                                : null),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
