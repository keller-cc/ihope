import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'config/server_config_loader.dart';
import 'services/auth_service.dart';
import 'services/auth_storage.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');

  if (Platform.isAndroid) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ihope_keep_alive',
        channelName: '消息连接',
        channelDescription: '保持 WebSocket 以接收新消息',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  final storage = AuthStorage();
  await bootstrapServerConfig(storage);
  final auth = AuthService(storage: storage);
  await AppConfig.refresh(auth.api);
  final notification = NotificationService();
  runApp(IHopeApp(auth: auth, notification: notification));
}
