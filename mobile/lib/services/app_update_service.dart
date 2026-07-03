import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../config/server_config.dart';

/// 下载并安装最新 App 包（Android APK；iOS 打开下载页）。
class AppUpdateService {
  AppUpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  String? get downloadUrl {
    final url = AppConfig.appDownloadUrl.trim();
    return url.isEmpty ? null : url;
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

    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/ihope-update.apk';

    await _dio.download(
      target,
      savePath,
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

    final result = await OpenFile.open(savePath);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开下载链接');
    }
  }
}
