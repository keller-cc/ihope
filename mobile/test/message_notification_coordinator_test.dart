import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:ihope/services/message_notification_coordinator.dart';

void main() {
  group('shouldShowBackgroundNotification', () {
    test('shows when background and from peer', () {
      expect(
        shouldShowBackgroundNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.paused,
          conversationOpen: false,
          isFromPeer: true,
        ),
        isTrue,
      );
    });

    test('suppresses when foreground', () {
      expect(
        shouldShowBackgroundNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.resumed,
          conversationOpen: false,
          isFromPeer: true,
        ),
        isFalse,
      );
    });

    test('suppresses when viewing conversation', () {
      expect(
        shouldShowBackgroundNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.paused,
          conversationOpen: true,
          isFromPeer: true,
        ),
        isFalse,
      );
    });

    test('suppresses when disabled', () {
      expect(
        shouldShowBackgroundNotification(
          notificationsEnabled: false,
          lifecycle: AppLifecycleState.hidden,
          conversationOpen: false,
          isFromPeer: true,
        ),
        isFalse,
      );
    });
  });
}
