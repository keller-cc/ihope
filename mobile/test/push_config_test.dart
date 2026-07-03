import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/config/push_config.dart';

void main() {
  test('pushPlatformTag maps channels', () {
    expect(pushPlatformTag(PushChannel.jpush), 'android_cn');
    expect(pushPlatformTag(PushChannel.fcm), 'android');
    expect(pushPlatformTag(PushChannel.none), 'unknown');
  });
}
