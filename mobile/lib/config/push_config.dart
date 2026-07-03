/// 编译时推送通道（与 Android productFlavor 对应）。
///
/// 国内：--flavor domestic --dart-define=PUSH_CHANNEL=jpush
/// 海外：--flavor global --dart-define=PUSH_CHANNEL=fcm
enum PushChannel {
  none,
  jpush,
  fcm,
}

PushChannel get pushChannel {
  const raw = String.fromEnvironment('PUSH_CHANNEL', defaultValue: 'none');
  return switch (raw) {
    'jpush' => PushChannel.jpush,
    'fcm' => PushChannel.fcm,
    _ => PushChannel.none,
  };
}

/// 极光 AppKey（国内包 dart-define 或 AndroidManifest 注入，二者至少其一）。
const kJPushAppKey = String.fromEnvironment('JPUSH_APP_KEY', defaultValue: '');

String get pushChannelLabel => switch (pushChannel) {
      PushChannel.jpush => '极光推送（国内 Android）',
      PushChannel.fcm => 'Firebase（海外 Android）',
      PushChannel.none => '未配置推送通道',
    };

/// 上报给后端的 platform 字段，用于路由极光 / FCM。
String pushPlatformTag(PushChannel channel) {
  return switch (channel) {
    PushChannel.jpush => 'android_cn',
    PushChannel.fcm => 'android',
    PushChannel.none => 'unknown',
  };
}
