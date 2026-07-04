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

    setUp(() {
      scroll = ScrollController();
      coord = ChatScrollCoordinator(
        scrollController: scroll,
        onChanged: () {},
        isMounted: () => true,
        onReachedBottom: () {},
      );
    });

    tearDown(() {
      coord.detach();
      scroll.dispose();
    });

    test('applyReadSnapshot seeds enter unread state', () {
      final readAt = DateTime(2026, 1, 1, 10);
      coord.applyReadSnapshot(readAt: readAt, unread: 3);

      expect(coord.readAtSnapshot, readAt);
      expect(coord.enterUnreadCount, 3);
      expect(coord.showJumpToUnread, isFalse);
      expect(coord.tailPinned, isTrue);
    });

    test('enter unread ids exclude tail new messages', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 1);
      coord.bindThread(messages, 'me');

      expect(coord.enterUnreadIds, {'unread1'});

      coord.handleTailAfterMessage(
        atBottom: false,
        fromPeer: true,
        messageId: 'tail-new',
        messages: messages,
        markRead: () async {},
      );

      expect(coord.enterUnreadIds, {'unread1'});
      expect(coord.belowUnreadCount, 1);
      expect(coord.showJumpToBottom, isTrue);
    });

    test('enter unread count decreases when marked seen scrolling up', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
        _msg('unread2', t0.add(const Duration(minutes: 2))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 2);
      coord.bindThread(messages, 'me');
      coord.syncEnterUnreadBubbleAfterLayout();

      coord.markUnreadSeenInSession('unread2');
      coord.updateUnreadVisibility(scrollingUp: true);

      expect(coord.enterUnreadCount, 1);
      expect(coord.showJumpToUnread, isTrue);
    });

    test('showJumpToUnread hides when all enter unread are on screen', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 1);
      coord.bindThread(messages, 'me');
      coord.markUnreadSeenInSession('unread1');
      coord.syncEnterUnreadBubbleAfterLayout();

      expect(coord.enterUnreadCount, 0);
      expect(coord.showJumpToUnread, isFalse);
    });

    test('tail new and enter unread bubbles can coexist', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 1);
      coord.bindThread(messages, 'me');
      coord.syncEnterUnreadBubbleAfterLayout();
      coord.addTailNewMessageForTest('tail-1');

      expect(coord.showJumpToUnread, isTrue);
      expect(coord.showJumpToBottom, isTrue);
      expect(coord.enterUnreadCount, 1);
      expect(coord.belowUnreadCount, 1);
    });

    test('handleTailAfterMessage at bottom marks read', () async {
      var marked = false;
      coord.addTailNewMessageForTest('x');
      final messages = [_msg('a', DateTime(2026, 1, 1, 10))];

      coord.handleTailAfterMessage(
        atBottom: true,
        fromPeer: true,
        messageId: 'b',
        messages: messages,
        markRead: () async {
          marked = true;
        },
      );

      expect(coord.tailPinned, isTrue);
      expect(marked, isTrue);
    });

    test('no divider when enter unread is 10 or fewer', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
        _msg('unread2', t0.add(const Duration(minutes: 2))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 2);
      coord.bindThread(messages, 'me');

      expect(coord.unreadDividerIndex, isNull);
    });

    test('divider at first unread when enter unread exceeds 10', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        for (var i = 1; i <= 12; i++)
          _msg('unread$i', t0.add(Duration(minutes: i))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 12);
      coord.bindThread(messages, 'me');

      expect(coord.unreadDividerIndex, 1);
    });

    test('divider stays fixed while enter count decreases', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        for (var i = 1; i <= 12; i++)
          _msg('unread$i', t0.add(Duration(minutes: i))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 12);
      coord.bindThread(messages, 'me');

      expect(coord.unreadDividerIndex, 1);

      coord.markUnreadSeenInSession('unread12');
      coord.updateUnreadVisibility(scrollingUp: true);

      expect(coord.enterUnreadCount, 11);
      expect(coord.unreadDividerIndex, 1);
    });

    test('beginUnreadSession does not reset progress on second present', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
        _msg('unread2', t0.add(const Duration(minutes: 2))),
      ];
      coord.beginUnreadSession(readAt: t0, unread: 2);
      coord.bindThread(messages, 'me');
      coord.markUnreadSeenInSession('unread2');
      coord.updateUnreadVisibility(scrollingUp: true);
      expect(coord.enterUnreadCount, 1);

      coord.beginUnreadSession(readAt: t0, unread: 2);
      expect(coord.enterUnreadCount, 1);
    });

    test('onJumpToUnread focuses target message', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        _msg('unread1', t0.add(const Duration(minutes: 1))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 1);
      coord.bindThread(messages, 'me');

      coord.onJumpToUnread(messages);

      expect(coord.focusedMessageId, isNull);
    });

    test('focusMessage sets and clears highlight id', () async {
      coord.focusMessage('msg-1');
      expect(coord.focusedMessageId, 'msg-1');

      await Future<void>.delayed(const Duration(milliseconds: 1450));
      expect(coord.focusedMessageId, isNull);
    });

    test('onJumpToNewMessages clears tail bubble without divider', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final read = _msg('read', t0);
      final tail1 = _msg('tail1', t0.add(const Duration(minutes: 1)));
      coord.applyReadSnapshot(readAt: t0, unread: 0);
      coord.bindThread([read], 'me');
      coord.addTailNewMessageForTest('tail1');

      expect(coord.unreadDividerIndex, isNull);

      final withTail = [read, tail1];
      coord.bindThread(withTail, 'me');
      coord.onJumpToNewMessages(withTail);

      expect(coord.showJumpToBottom, isFalse);
      expect(coord.belowUnreadCount, 0);
      expect(coord.unreadDividerIndex, isNull);
    });

    test('divider clears when leaving session', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [
        _msg('read', t0),
        for (var i = 1; i <= 12; i++)
          _msg('unread$i', t0.add(Duration(minutes: i))),
      ];
      coord.applyReadSnapshot(readAt: t0, unread: 12);
      coord.bindThread(messages, 'me');
      expect(coord.unreadDividerIndex, 1);

      coord.applyReadSnapshot(readAt: t0, unread: 12);
      expect(coord.unreadDividerIndex, isNull);
    });

    test('tail new alone does not show divider', () {
      final t0 = DateTime(2026, 1, 1, 10);
      final messages = [_msg('read', t0)];
      coord.applyReadSnapshot(readAt: t0, unread: 0);
      coord.bindThread(messages, 'me');

      coord.handleTailAfterMessage(
        atBottom: false,
        fromPeer: true,
        messageId: 'tail-1',
        messages: messages,
        markRead: () async {},
      );

      expect(coord.unreadDividerIndex, isNull);
    });

    testWidgets('scroll lock preserves pixels when tail grows in reverse list',
        (tester) async {
      final scroll = ScrollController();
      final messages = ValueNotifier<List<String>>(
        List.generate(20, (i) => 'msg-$i'),
      );
      var changed = 0;
      final coord = ChatScrollCoordinator(
        scrollController: scroll,
        onChanged: () => changed++,
        isMounted: () => true,
        onReachedBottom: () {},
      );
      coord.attach();
      addTearDown(() {
        coord.detach();
        scroll.dispose();
        messages.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<List<String>>(
              valueListenable: messages,
              builder: (context, items, _) {
                // ignore: unused_local_variable
                final _ = changed;
                return CustomScrollView(
                  reverse: true,
                  controller: scroll,
                  slivers: [
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final msgIndex = items.length - 1 - index;
                          return SizedBox(
                            height: 48,
                            child: Text(items[msgIndex]),
                          );
                        },
                        childCount: items.length,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();

      coord.tailPinned = false;
      final before = scroll.position.pixels;

      coord.beginScrollLockForTailInsert();
      messages.value = [...messages.value, 'msg-new'];
      await tester.pump();
      coord.endScrollLockAfterTailInsert();
      await tester.pumpAndSettle();

      expect(scroll.position.pixels, closeTo(before, 1.0));
    });
  });
}
