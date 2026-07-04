import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
class CloudDriveLauncher {
  CloudDriveLauncher._();

  static const url = String.fromEnvironment(
    'CLOUD_DRIVE_URL',
    defaultValue: 'https://1t1.org',
  );

  static const label = '1t1网盘';

  static Future<void> open() async {
    final uri = Uri.parse(AppConfig.cloudDriveUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      throw StateError('无法打开 $label');
    }
  }
}

/// 按字节数估算传输超时（单次 HTTP，非分片续传）。
Duration transferTimeoutForBytes(int bytes) {
  // 按 ~256KB/s 估算，另加 90s 握手/加密余量；上限 1 小时
  final sec = (bytes / (256 * 1024)).ceil() + 90;
  return Duration(seconds: sec.clamp(120, 3600));
}

String friendlyTransferError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('timeout') ||
      msg.contains('timed out') ||
      msg.contains('deadline')) {
    return '上传超时，请检查网络后重试（当前为整包上传，断网需重新发送）';
  }
  if (msg.contains('connection') ||
      msg.contains('socket') ||
      msg.contains('network')) {
    return '网络中断，请稍后重试（当前为整包上传，不支持断点续传）';
  }
  if (msg.contains('validation') || msg.contains('invalid upload')) {
    return '文件上传被拒绝，请更新服务端后重试，或使用 1t1 网盘';
  }
  return error.toString();
}
