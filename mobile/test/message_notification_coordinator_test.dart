import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:ihope/services/message_notification_coordinator.dart';

void main() {
  group('shouldShowInAppMessageBanner', () {
    test('shows on home screen when not viewing chat', () {
      expect(
        shouldShowInAppMessageBanner(
          activelyViewingConversation: false,
          isFromPeer: true,
        ),
        isTrue,
      );
    });

    test('suppresses when actively viewing conversation', () {
      expect(
        shouldShowInAppMessageBanner(
          activelyViewingConversation: true,
          isFromPeer: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowMessageNotification', () {
    test('shows when background even if conversation was open', () {
      expect(
        shouldShowMessageNotification(
          notificationsEnabled: true,
          activelyViewingConversation: false,
          isFromPeer: true,
        ),
        isTrue,
      );
    });

    test('shows on home screen when not viewing chat', () {
      expect(
        shouldShowMessageNotification(
          notificationsEnabled: true,
          activelyViewingConversation: false,
          isFromPeer: true,
        ),
        isTrue,
      );
    });

    test('suppresses when actively viewing conversation in foreground', () {
      expect(
        shouldShowMessageNotification(
          notificationsEnabled: true,
          activelyViewingConversation: true,
          isFromPeer: true,
        ),
        isFalse,
      );
    });

    test('shows when paused from group chat (not actively viewing)', () {
      expect(
        shouldShowBackgroundNotification(
          notificationsEnabled: true,
          lifecycle: AppLifecycleState.paused,
          conversationOpen: true,
          isFromPeer: true,
        ),
        isTrue,
      );
    });

    test('suppresses when disabled', () {
      expect(
        shouldShowMessageNotification(
          notificationsEnabled: false,
          activelyViewingConversation: false,
          isFromPeer: true,
        ),
        isFalse,
      );
    });
  });

  group('messageNotifySurface', () {
    test('in-app when resumed', () {
      expect(
        messageNotifySurface(AppLifecycleState.resumed),
        MessageNotifySurface.inApp,
      );
    });

    test('in-app when inactive (visible foreground)', () {
      expect(
        messageNotifySurface(AppLifecycleState.inactive),
        MessageNotifySurface.inApp,
      );
      expect(isAppForegroundLifecycle(AppLifecycleState.inactive), isTrue);
    });

    test('system when paused', () {
      expect(
        messageNotifySurface(AppLifecycleState.paused),
        MessageNotifySurface.system,
      );
    });
  });
}
