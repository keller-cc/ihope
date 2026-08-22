import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_release_config.dart';
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
  String? _downloadSourceLabel;

  @override
  void initState() {
    super.initState();
    _checker = VersionCheckService(widget.auth.api);
    _updater = AppUpdateService();
    unawaited(_runCheck());
  }

  @override
  void dispose() {
    if (_downloading) {
      _updater.cancelDownload();
    }
    super.dispose();
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

  Future<void> _startDownload({
    required String sourceLabel,
    required Future<String?> urlFuture,
  }) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _downloadError = null;
      _downloadSourceLabel = sourceLabel;
    });
    try {
      final url = await urlFuture;
      if (url == null || url.isEmpty) {
        throw StateError('无法获取下载地址');
      }
      await _updater.downloadAndInstall(
        url: url,
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
    } on AppDownloadCancelled {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消下载')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _downloadError = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadProgress = null;
          _downloadSourceLabel = null;
        });
      }
    }
  }

  Future<void> _downloadFromServer() {
    final url = _updater.downloadUrl;
    if (url == null || url.isEmpty) {
      setState(() => _downloadError = '服务端未配置下载地址');
      return Future.value();
    }
    return _startDownload(
      sourceLabel: '服务器',
      urlFuture: Future.value(url),
    );
  }

  Future<void> _downloadFromGithub() {
    return _startDownload(
      sourceLabel: 'GitHub',
      urlFuture: _updater.resolveGithubLatestApkUrl(),
    );
  }

  void _cancelDownload() {
    _updater.cancelDownload();
  }

  Future<void> _openGithubInBrowser() async {
    try {
      await _updater.openGithubReleases();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制链接')),
    );
  }

  bool get _canDownloadServer =>
      AppConfig.appDownloadUrl.trim().isNotEmpty && !_downloading;

  bool get _shouldPromoteDownload =>
      _result?.status == VersionCheckStatus.serverNewer;

  String get _githubUrl => _updater.githubReleasesUrl;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final scheme = Theme.of(context).colorScheme;
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
            const SizedBox(height: 24),
            if (result != null) _statusCard(result),
            const SizedBox(height: 24),
            Text(
              '下载渠道',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            _downloadChannelCard(
              icon: Icons.cloud_download_outlined,
              title: '服务器直链',
              subtitle: AppConfig.appDownloadUrl.trim().isNotEmpty
                  ? AppConfig.appDownloadUrl
                  : '未配置（uploads/releases/latest.apk 或 APP_DOWNLOAD_URL）',
              actions: [
                if (_canDownloadServer)
                  FilledButton.icon(
                    onPressed: () => unawaited(_downloadFromServer()),
                    icon: const Icon(Icons.download),
                    label: Text(_shouldPromoteDownload ? '下载最新版' : '下载安装包'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _downloadChannelCard(
              icon: Icons.link_rounded,
              title: 'GitHub Releases',
              subtitle: _githubUrl,
              linkUrl: _githubUrl,
              onCopy: () => unawaited(_copyText(_githubUrl)),
              actions: [
                OutlinedButton.icon(
                  onPressed: _downloading ? null : () => unawaited(_openGithubInBrowser()),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('在浏览器打开'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _downloading ? null : () => unawaited(_downloadFromGithub()),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('从 GitHub 下载'),
                ),
              ],
            ),
            if (_downloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _downloadProgress != null && _downloadProgress! > 0
                    ? _downloadProgress
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _downloadProgress != null
                          ? '正在从${_downloadSourceLabel ?? ''}下载 '
                              '${(_downloadProgress! * 100).toStringAsFixed(0)}%'
                          : '准备下载…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelDownload,
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
            if (_downloadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _downloadError!,
                style: TextStyle(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Android：下载完成后会弹出系统安装界面。\n'
              'GitHub 渠道需能访问 github.com；失败时可点「在浏览器打开」手动下载 '
              '${AppReleaseConfig.domesticApkAssetName}。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _downloadChannelCard({
    required IconData icon,
    required String title,
    required String subtitle,
    String? linkUrl,
    VoidCallback? onCopy,
    required List<Widget> actions,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (onCopy != null)
                  IconButton(
                    tooltip: '复制链接',
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (linkUrl != null)
              InkWell(
                onTap: () => unawaited(
                  launchUrl(
                    Uri.parse(linkUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: scheme.primary.withValues(alpha: 0.5),
                      ),
                ),
              )
            else
              SelectableText(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
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
