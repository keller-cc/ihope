import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/models/message.dart';
import 'package:ihope/services/message_cache_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ChatMessage _msg(String id, DateTime at, {String? plaintext}) {
  return ChatMessage(
    id: id,
    conversationId: 'conv-1',
    senderId: 'alice',
    type: 'text',
    ciphertext: 'cipher-$id',
    createdAt: at,
    plaintext: plaintext,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('MessageCacheStore saves and loads messages in order', () async {
    final store = MessageCacheStore(
      openDatabaseForTest: () => openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE messages (
              user_id TEXT NOT NULL,
              conversation_id TEXT NOT NULL,
              message_id TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              PRIMARY KEY (user_id, conversation_id, message_id)
            )
          ''');
        },
      ),
    );

    final t1 = DateTime(2026, 1, 1, 10);
    final t2 = DateTime(2026, 1, 1, 11);
    final messages = [
      _msg('b', t2, plaintext: 'second'),
      _msg('a', t1, plaintext: 'first'),
    ];

    await store.replaceConversation('user-1', 'conv-1', messages);
    final loaded = await store.load('user-1', 'conv-1');

    expect(loaded.map((m) => m.id).toList(), ['a', 'b']);
    expect(loaded.first.plaintext, 'first');
    expect(loaded.last.plaintext, 'second');

    await store.clearUser('user-1');
    expect(await store.load('user-1', 'conv-1'), isEmpty);
    await store.close();
  });

  test('encodePayload strips inline preview so the row stays small', () {
    final preview = base64Encode(List<int>.filled(500000, 7));
    final msg = ChatMessage(
      id: 'img-1',
      conversationId: 'conv-1',
      senderId: 'alice',
      type: 'image',
      ciphertext: 'x' * 100,
      createdAt: DateTime.utc(2026, 1, 1),
      plaintext: jsonEncode({
        'media': 'image',
        'local': true,
        'mime': 'image/jpeg',
        'name': 'a.jpg',
        'preview_b64': preview,
      }),
    );
    final encoded = MessageCacheStore.encodePayload(msg);
    expect(encoded, isNotNull);
    expect(encoded!.contains('preview_b64'), isFalse);
    expect(jsonDecode(encoded)['plaintext'], contains('"local":true'));
  });
}
