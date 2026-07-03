import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android 前台服务：进程存活时保持 WebSocket，类似 QQ「正在运行」。
class BackgroundKeepAliveService {
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<void> start() async {
    if (!isSupported) return;
    if (await isRunning) return;

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'IHope',
      notificationText: '正在接收新消息',
      callback: _keepAliveCallback,
    );
    if (result is! ServiceRequestSuccess) {
      debugPrint('BackgroundKeepAliveService: start failed ($result)');
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    if (!await isRunning) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void _keepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}
}
