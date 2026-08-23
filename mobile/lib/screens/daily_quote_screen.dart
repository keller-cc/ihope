import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class DailyQuoteScreen extends StatefulWidget {
  const DailyQuoteScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<DailyQuoteScreen> createState() => _DailyQuoteScreenState();
}

class _DailyQuoteScreenState extends State<DailyQuoteScreen> {
  DailyQuote? _quote;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    if (!force) {
      final stored = await widget.auth.peekStoredTodayQuote();
      if (!mounted) return;
      if (stored != null) {
        setState(() {
          _quote = stored;
          _error = null;
          _loading = false;
        });
        return;
      }
    }
    setState(() {
      _loading = _quote == null;
      _error = null;
    });
    try {
      final q = await widget.auth.fetchTodayQuote(force: force);
      if (!mounted) return;
      setState(() {
        _quote = q.hasContent ? q : null;
        _loading = false;
        _error = q.hasContent ? null : '暂无金句内容';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _quote == null ? '无法加载金句' : null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('今日金句'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed:
                _loading ? null : () => unawaited(_load(force: _error != null)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loading ? null : () => unawaited(_load(force: true)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    if (_quote?.date != null)
                      Text(
                        _quote!.date!,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                            ),
                      ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _quote?.body ?? '',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.65,
                            fontSize: 17,
                          ),
                    ),
                    if (_quote?.author != null &&
                        _quote!.author!.trim().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SelectableText(
                        '来自@${_quote!.author!.trim()}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
