import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/services/remote_push_handler.dart';

void main() {
  test('chatMessageFromPushData parses ciphertext payload', () {
    final msg = chatMessageFromPushData({
      'conversation_id': 'c1',
      'message_id': 'm1',
      'sender_id': 'u2',
      'type': 'text',
      'ciphertext': 'encrypted-blob',
      'epoch': '3',
    });
    expect(msg, isNotNull);
    expect(msg!.ciphertext, 'encrypted-blob');
    expect(msg.epoch, 3);
  });

  test('chatMessageFromPushData rejects missing ciphertext', () {
    expect(
      chatMessageFromPushData({'conversation_id': 'c1'}),
      isNull,
    );
  });
}
