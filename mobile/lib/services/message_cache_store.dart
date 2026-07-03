import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/message.dart';

/// 按用户/会话持久化消息缓存（SQLite，替代 secure storage 大 JSON）。
class MessageCacheStore {
  MessageCacheStore({Future<Database> Function()? openDatabaseForTest})
      : _openDatabaseForTest = openDatabaseForTest;

  final Future<Database> Function()? _openDatabaseForTest;
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    _db = _openDatabaseForTest != null
        ? await _openDatabaseForTest!()
        : await _openPersistent();
    return _db!;
  }

  Future<Database> _openPersistent() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'ihope_messages.db');
    return openDatabase(
      path,
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
        await db.execute(
          'CREATE INDEX idx_messages_conv ON messages(user_id, conversation_id, created_at)',
        );
      },
    );
  }

  Future<List<ChatMessage>> load(String userId, String conversationId) async {
    final db = await _database();
    final rows = await db.query(
      'messages',
      columns: ['payload'],
      where: 'user_id = ? AND conversation_id = ?',
      whereArgs: [userId, conversationId],
      orderBy: 'created_at ASC',
    );
    final list = <ChatMessage>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row['payload']! as String) as Map<String, dynamic>;
        list.add(ChatMessage.fromJson(json));
      } catch (_) {}
    }
    return list;
  }

  Future<void> replaceConversation(
    String userId,
    String conversationId,
    List<ChatMessage> messages,
  ) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.delete(
        'messages',
        where: 'user_id = ? AND conversation_id = ?',
        whereArgs: [userId, conversationId],
      );
      if (messages.isEmpty) return;
      final batch = txn.batch();
      for (final m in messages) {
        batch.insert(
          'messages',
          {
            'user_id': userId,
            'conversation_id': conversationId,
            'message_id': m.id,
            'payload': jsonEncode(m.toJson()),
            'created_at': m.createdAt.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> clearUser(String userId) async {
    final db = await _database();
    await db.delete('messages', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> clearAll() async {
    final db = await _database();
    await db.delete('messages');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
