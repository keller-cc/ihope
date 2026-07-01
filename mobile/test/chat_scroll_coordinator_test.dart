import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/screens/chat/chat_scroll_coordinator.dart';

ChatMessage _msg(String id, DateTime at, {String senderId = 'peer'}) {
  return ChatMessage(
    id: id,
    conversationId: 'conv-1',
    senderId: senderId,
    type: 'text',
    ciphertext: 'cipher',
    createdAt: at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatScrollCoordinator', () {
    late ScrollController scroll;
    late ChatScrollCoordinator coord;
    var changed = 0;

    setUp(() {
      changed = 0;
      scroll = ScrollController();
      coord = ChatScrollCoordinator(
        scrollController: scroll,
        onChanged: () => changed++,
        isMounted: () => true,
        onReachedBottom: () {},
        firstUnreadIndexIn: (messages, readAt) {
          for (var i = 0; i < messages.length; i++) {
            final m = messages[i];
            if (m.senderId == 'me') continue;
            if (readAt == null || m.createdAt.isAfter(readAt)) return i;
          }
          return null;
        },
      );
    });

    tearDown(() {
      coord.detach();
      scroll.dispose();
    });

    test('applyReadSnapshot sets unread bubble state', () {
      final readAt = DateTime(2026, 1, 1, 10);
      coord.applyReadSnapshot(readAt: readAt, unread: 3);

      expect(coord.readAtSnapshot, readAt);
      expect(coord.enterUnreadCount, 3);
      expect(coord.showJumpToUnread, isTrue);
      expect(coord.unreadDividerAtIndex, isNull);
      expect(coord.tailPinned, isTrue);
    });

    test('maybeMarkReadWithLast clears unread when pinned and no bubble', () {
      coord.applyReadSnapshot(readAt: null, unread: 0);
      coord.tailPinned = true;
      final last = _msg('m1', DateTime(2026, 1, 1, 12));

      coord.maybeMarkReadWithLast(last);

      expect(coord.readAtSnapshot, last.createdAt);
      expect(coord.enterUnreadCount, 0);
      expect(coord.showJumpToUnread, isFalse);
    });

    test('maybeMarkReadWithLast keeps bubble while jump-to-unread visible', () {
      coord.applyReadSnapshot(readAt: null, unread: 2);
      final last = _msg('m1', DateTime(2026, 1, 1, 12));

      coord.maybeMarkReadWithLast(last);

      expect(coord.enterUnreadCount, 2);
      expect(coord.showJumpToUnread, isTrue);
      expect(coord.readAtSnapshot, isNull);
    });

    test('handleTailAfterMessage at bottom clears divider and marks read', () async {
      var marked = false;
      coord.unreadDividerAtIndex = 1;
      coord.belowUnreadCount = 2;
      coord.showJumpToBottom = true;
      final messages = [_msg('a', DateTime(2026, 1, 1, 10))];

      coord.handleTailAfterMessage(
        atBottom: true,
        fromPeer: true,
        messages: messages,
        markRead: () async {
          marked = true;
        },
      );

      expect(coord.tailPinned, isTrue);
      expect(coord.belowUnreadCount, 0);
      expect(coord.showJumpToBottom, isFalse);
      expect(coord.unreadDividerAtIndex, isNull);
      expect(marked, isTrue);
    });

    test('handleTailAfterMessage scrolled up increments new message count', () async {
      coord.handleTailAfterMessage(
        atBottom: false,
        fromPeer: true,
        messages: [_msg('a', DateTime(2026, 1, 1, 10))],
        markRead: () async {},
      );

      expect(coord.belowUnreadCount, 1);
      expect(coord.showJumpToBottom, isTrue);
      expect(changed, greaterThan(0));
    });

    test('handleTailAfterMessage ignores own messages when scrolled up', () async {
      coord.handleTailAfterMessage(
        atBottom: false,
        fromPeer: false,
        messages: [_msg('a', DateTime(2026, 1, 1, 10), senderId: 'me')],
        markRead: () async {},
      );

      expect(coord.belowUnreadCount, 0);
      expect(coord.showJumpToBottom, isFalse);
    });

    test('onJumpToUnread hides chip and pins divider at first unread index', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread', t0.add(const Duration(minutes: 1))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 1);

      coord.onJumpToUnread(messages);

      expect(coord.showJumpToUnread, isFalse);
      expect(coord.enterUnreadCount, 0);
      expect(coord.unreadDividerAtIndex, 1);
    });

    test('countRemainingUnreadAboveViewport ignores below-viewport unreads', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('m0', t0),
        _msg('m1', t0.add(const Duration(minutes: 1))),
        _msg('m2', t0.add(const Duration(minutes: 2))),
        _msg('m3', t0.add(const Duration(minutes: 3))),
      ];

      final remaining = ChatScrollCoordinator.countRemainingUnreadAboveViewport(
        messages: messages,
        meId: 'me',
        readAt: null,
        isVisibleInViewport: (id) => id == 'm2' || id == 'm3',
      );

      expect(remaining, 2);
    });

    test('countRemainingUnreadAboveViewport drops as older unreads enter view', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('m0', t0),
        _msg('m1', t0.add(const Duration(minutes: 1))),
        _msg('m2', t0.add(const Duration(minutes: 2))),
      ];

      final scrolledUp = ChatScrollCoordinator.countRemainingUnreadAboveViewport(
        messages: messages,
        meId: 'me',
        readAt: null,
        isVisibleInViewport: (id) => id == 'm0' || id == 'm1' || id == 'm2',
      );
      final atBottom = ChatScrollCoordinator.countRemainingUnreadAboveViewport(
        messages: messages,
        meId: 'me',
        readAt: null,
        isVisibleInViewport: (id) => id == 'm2',
      );

      expect(atBottom, 2);
      expect(scrolledUp, 0);
      expect(scrolledUp, lessThan(atBottom));
    });
  });
}
