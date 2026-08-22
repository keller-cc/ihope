import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';

/// QQ 机器人：离线消息提醒、每日诗词 / 金句 / 资讯图。
class QqBotSettingsScreen extends StatefulWidget {
  const QqBotSettingsScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<QqBotSettingsScreen> createState() => _QqBotSettingsScreenState();
}

class _QqBotSettingsScreenState extends State<QqBotSettingsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _botEnabled = false;
  bool _bound = false;
  bool _doorbell = true;
  bool _poetry = true;
  bool _quotes = true;
  bool _news = true;
  String? _bindCode;
  String? _hint;
  String? _expiresAt;

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
      final s = await widget.auth.fetchQqBotStatus();
      if (!mounted) return;
      setState(() {
        _botEnabled = s.botEnabled;
        _bound = s.bound;
        _doorbell = s.doorbellEnabled;
        _poetry = s.poetryEnabled;
        _quotes = s.quotesEnabled;
        _news = s.newsEnabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _createCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.auth.createQqBotBindCode();
      if (!mounted) return;
      setState(() {
        _bindCode = r.code;
        _hint = r.botAddHint;
        _expiresAt = r.expiresAt;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _patch({
    bool? doorbell,
    bool? poetry,
    bool? quotes,
    bool? news,
  }) async {
    setState(() => _busy = true);
    try {
      final s = await widget.auth.patchQqBot(
        doorbellEnabled: doorbell,
        poetryEnabled: poetry,
        quotesEnabled: quotes,
        newsEnabled: news,
      );
      if (!mounted) return;
      setState(() {
        _bound = s.bound;
        _doorbell = s.doorbellEnabled;
        _poetry = s.poetryEnabled;
        _quotes = s.quotesEnabled;
        _news = s.newsEnabled;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _unbind() async {
    setState(() => _busy = true);
    try {
      await widget.auth.unbindQqBot();
      if (!mounted) return;
      setState(() {
        _bound = false;
        _bindCode = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QQ 提醒')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (!_botEnabled)
                  const Text(
                    '服务端尚未启用 QQ 机器人（QQ_BOT_ENABLED）。启用并配置官方 AppID 后，可使用离线消息提醒与每日图文推送。',
                  )
                else ...[
                  Text(
                    _bound ? '已绑定 QQ 机器人' : '尚未绑定',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _hint ??
                        '在 App 获取绑定码 → QQ 添加官方机器人 → 将绑定码发给机器人。'
                        '离线时为文字提醒；诗词、金句与资讯为图片推送。',
                  ),
                  const SizedBox(height: 16),
                  if (!_bound) ...[
                    FilledButton(
                      onPressed: _busy ? null : _createCode,
                      child: const Text('获取绑定码'),
                    ),
                    if (_bindCode != null) ...[
                      const SizedBox(height: 16),
                      SelectableText(
                        _bindCode!,
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              letterSpacing: 8,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      if (_expiresAt != null)
                        Text('有效至 $_expiresAt', textAlign: TextAlign.center),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _bindCode!));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制绑定码')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('复制'),
                      ),
                    ],
                  ] else ...[
                    SwitchListTile(
                      title: const Text('离线消息提醒'),
                      subtitle: const Text('不在线时通过 QQ 通知你有新聊天消息'),
                      value: _doorbell,
                      onChanged: _busy
                          ? null
                          : (v) => unawaited(_patch(doorbell: v)),
                    ),
                    SwitchListTile(
                      title: const Text('每日诗词（图片）'),
                      subtitle: const Text('古典诗词图卡；QQ 可发送「诗词」立即获取'),
                      value: _poetry,
                      onChanged: _busy
                          ? null
                          : (v) => unawaited(_patch(poetry: v)),
                    ),
                    SwitchListTile(
                      title: const Text('每日金句（图片）'),
                      subtitle: const Text('服务端文案库；首页左侧面板可阅「今日金句」'),
                      value: _quotes,
                      onChanged: _busy
                          ? null
                          : (v) => unawaited(_patch(quotes: v)),
                    ),
                    SwitchListTile(
                      title: const Text('每日资讯（图片）'),
                      subtitle: const Text('60s 读世界；QQ 可发送「新闻」'),
                      value: _news,
                      onChanged: _busy
                          ? null
                          : (v) => unawaited(_patch(news: v)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _unbind,
                      child: const Text('解绑 QQ'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _createCode,
                      child: const Text('重新获取绑定码（换号）'),
                    ),
                    if (_bindCode != null) ...[
                      SelectableText(
                        _bindCode!,
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ],
              ],
            ),
    );
  }
}
