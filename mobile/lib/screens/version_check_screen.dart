import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/app_version.dart';
import '../services/app_update_service.dart';
import '../services/auth_service.dart';
import '../services/version_check_service.dart';
import '../utils/version_label.dart';

class VersionCheckScreen extends StatefulWidget {
  const VersionCheckScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<VersionCheckScreen> createState() => _VersionCheckScreenState();
}

class _VersionCheckScreenState extends State<VersionCheckScreen> {
  late final VersionCheckService _checker;
  late final AppUpdateService _updater;
  VersionCheckResult? _result;
  String? _appLabel;
  bool _loading = true;
  bool _downloading = false;
  double? _downloadProgress;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checker = VersionCheckService(widget.auth.api);
    _updater = AppUpdateService();
    unawaited(_runCheck());
  }

  Future<void> _runCheck() async {
    setState(() {
      _loading = true;
      _downloadError = null;
    });
    final appLabel = await AppVersionInfo.displayLabel();
    final result = await _checker.check();
    if (!mounted) return;
    setState(() {
      _appLabel = appLabel;
      _result = result;
      _loading = false;
    });
  }

  Future<void> _downloadLatest() async {
    if (_updater.downloadUrl == null || _updater.downloadUrl!.isEmpty) {
      setState(() => _downloadError = '服务端未配置下载地址');
      return;
    }
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });
    try {
      await _updater.downloadAndInstall(
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      if (!Platform.isAndroid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已在浏览器打开下载页')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _downloadError = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
        });
      }
    }
  }

  bool get _canDownload =>
      AppConfig.appDownloadUrl.trim().isNotEmpty && !_downloading;

  bool get _shouldPromoteDownload =>
      _result?.status == VersionCheckStatus.serverNewer;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('检查版本'),
        actions: [
          IconButton(
            onPressed: _loading || _downloading ? null : () => unawaited(_runCheck()),
            icon: const Icon(Icons.refresh),
            tooltip: '重新检查',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _row('本机版本', _appLabel ?? '—'),
            const SizedBox(height: 12),
            _row('服务端版本', result?.serverLabel ?? '—'),
            if (AppConfig.appDownloadUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              _row('下载地址', AppConfig.appDownloadUrl),
            ],
            const SizedBox(height: 24),
            if (result != null) _statusCard(result),
            if (_canDownload) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => unawaited(_downloadLatest()),
                icon: const Icon(Icons.download),
                label: Text(_shouldPromoteDownload ? '下载最新版' : '下载安装包'),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _downloadProgress != null && _downloadProgress! > 0
                    ? _downloadProgress
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadProgress != null
                    ? '下载中 ${(_downloadProgress! * 100).toStringAsFixed(0)}%'
                    : '准备下载…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_downloadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _downloadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Android：下载完成后会弹出系统安装界面。\n'
              '将 APK 放到服务端 uploads/releases/latest.apk，'
              '或在 deploy/.env 设置 APP_DOWNLOAD_URL。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }

  Widget _statusCard(VersionCheckResult result) {
    final scheme = Theme.of(context).colorScheme;
    late final Color bg;
    late final IconData icon;
    switch (result.status) {
      case VersionCheckStatus.upToDate:
        bg = scheme.primaryContainer;
        icon = Icons.check_circle_outline;
      case VersionCheckStatus.serverNewer:
        bg = scheme.errorContainer;
        icon = Icons.system_update_alt;
      case VersionCheckStatus.appNewer:
        bg = scheme.secondaryContainer;
        icon = Icons.info_outline;
      case VersionCheckStatus.parseError:
      case VersionCheckStatus.networkError:
        bg = scheme.surfaceContainerHighest;
        icon = Icons.warning_amber_outlined;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.message ?? '—',
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
