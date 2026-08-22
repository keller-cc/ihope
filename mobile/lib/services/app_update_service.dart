import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/app_release_config.dart';
import '../config/server_config.dart';

/// 用户主动取消下载。
class AppDownloadCancelled implements Exception {
  const AppDownloadCancelled();
}

/// 下载并安装最新 App 包（Android APK；iOS 打开下载页）。
class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  CancelToken? _activeCancelToken;

  String? get downloadUrl {
    final url = AppConfig.appDownloadUrl.trim();
    return url.isEmpty ? null : url;
  }

  String get githubReleasesUrl =>
      AppReleaseConfig.githubReleasesUrl.trim().isNotEmpty
          ? AppReleaseConfig.githubReleasesUrl.trim()
          : AppReleaseConfig.defaultGithubReleasesUrl;

  void cancelDownload() {
    final token = _activeCancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('user_cancelled');
    }
  }

  static String resolveDownloadUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = ServerConfig.apiBase.replaceAll(RegExp(r'/+$'), '');
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$base$path';
  }

  Future<void> openGithubReleases() async {
    await _openExternal(githubReleasesUrl);
  }

  /// 从 GitHub Releases API 解析 domestic APK 直链。
  Future<String?> resolveGithubLatestApkUrl() async {
    final repo = AppReleaseConfig.defaultGithubRepo;
    final apiUrl = AppReleaseConfig.githubApiLatestUrl(repo);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        apiUrl,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/vnd.github+json'},
        ),
      );
      final data = res.data;
      if (data == null) return null;
      final assets = data['assets'];
      if (assets is! List) return null;
      for (final raw in assets) {
        if (raw is! Map<String, dynamic>) continue;
        final name = raw['name'] as String? ?? '';
        if (name == AppReleaseConfig.domesticApkAssetName ||
            name.endsWith('.apk')) {
          final url = raw['browser_download_url'] as String?;
          if (url != null && url.isNotEmpty) return url;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> downloadAndInstall({
    String? url,
    void Function(double progress)? onProgress,
  }) async {
    final target = resolveDownloadUrl(url ?? downloadUrl ?? '');
    if (target.isEmpty) {
      throw StateError('未配置下载地址');
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      await _openExternal(target);
      return;
    }

    if (Platform.isIOS) {
      await _openExternal(target);
      return;
    }

    _activeCancelToken?.cancel('superseded');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/ihope-update.apk';

    try {
      await _dio.download(
        target,
        savePath,
        cancelToken: cancelToken,
        options: Options(
          receiveTimeout: const Duration(hours: 1),
          sendTimeout: const Duration(minutes: 2),
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress?.call(received / total);
        },
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        try {
          final partial = File(savePath);
          if (partial.existsSync()) await partial.delete();
        } catch (_) {}
        throw const AppDownloadCancelled();
      }
      throw StateError(e.message ?? '下载失败');
    } finally {
      if (_activeCancelToken == cancelToken) {
        _activeCancelToken = null;
      }
    }

    if (cancelToken.isCancelled) {
      throw const AppDownloadCancelled();
    }

    final result = await OpenFile.open(savePath);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开链接');
    }
  }
}
