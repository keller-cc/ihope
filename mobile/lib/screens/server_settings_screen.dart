import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/env.dart';
import '../config/server_config.dart';
import '../config/server_config_loader.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

/// 配置后端 API 地址（保存后需重新登录生效）。
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({
    super.key,
    required this.auth,
    this.requireLogoutOnSave = true,
  });

  final AuthService auth;
  final bool requireLogoutOnSave;

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final TextEditingController _url;
  bool _busy = false;
  String? _hint;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: ServerConfig.apiBase);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
    });
    try {
      final base = ServerConfig.normalizeApiBase(_url.text);
      final client = ApiClient(baseUrl: base);
      final res = await client.getJson('/api/health');
      if (res['ok'] == true) {
        await AppConfig.refresh(client);
      }
      if (!mounted) return;
      setState(() {
        _hint = res['ok'] == true ? '连接成功：$base' : '服务器响应异常';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _hint = null;
    });
    try {
      final normalized = ServerConfig.normalizeApiBase(_url.text);
      await applyServerBaseUrl(widget.auth.storage, normalized);
      widget.auth.api.setBaseUrl(normalized);
      await AppConfig.refresh(widget.auth.api);
      if (!mounted) return;
      if (widget.requireLogoutOnSave) {
        Navigator.of(context).pop('logout');
        return;
      }
      setState(() {
        _hint = '已保存。WebSocket 将在下次连接时使用新地址。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetDefault() async {
    await resetServerBaseUrl(widget.auth.storage);
    widget.auth.api.setBaseUrl(Env.defaultApiBase);
    if (!mounted) return;
    setState(() => _url.text = Env.defaultApiBase);
    if (widget.requireLogoutOnSave) {
      Navigator.of(context).pop('logout');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器设置')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '后台服务地址（HTTP/HTTPS）\n'
            'WebSocket 将自动使用对应的 ws/wss 地址。',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'API 地址',
              hintText: 'http://192.168.1.10:8080',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_hint != null) ...[
            const SizedBox(height: 12),
            Text(_hint!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _testConnection,
            child: const Text('测试连接'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('保存并重新登录'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _resetDefault,
            child: Text('恢复默认（${Env.defaultApiBase}）'),
          ),
          const SizedBox(height: 24),
          Text(
            '编译默认：${Env.defaultApiBase}\n'
            '当前生效：${ServerConfig.apiBase}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
