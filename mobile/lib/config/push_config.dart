/// 编译时推送通道（与 Android productFlavor 对应）。
///
/// 国内：默认 none（离线用 QQ 门铃）；海外：--dart-define=PUSH_CHANNEL=fcm
enum PushChannel {
  none,
  fcm,
}

PushChannel get pushChannel {
  const raw = String.fromEnvironment('PUSH_CHANNEL', defaultValue: 'none');
  return switch (raw) {
    'fcm' => PushChannel.fcm,
    // 历史 jpush 配置视为未启用
    _ => PushChannel.none,
  };
}

String get pushChannelLabel => switch (pushChannel) {
      PushChannel.fcm => 'Firebase（海外 Android）',
      PushChannel.none => '未配置推送通道（国内可用 QQ 门铃）',
    };

/// 上报给后端的 platform 字段，用于路由 FCM。
String pushPlatformTag(PushChannel channel) {
  return switch (channel) {
    PushChannel.fcm => 'android',
    PushChannel.none => 'unknown',
  };
}
