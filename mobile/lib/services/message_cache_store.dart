import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/message.dart';
import '../utils/media_local_cache.dart';

/// 按用户/会话持久化消息缓存（SQLite，替代 secure storage 大 JSON）。
class MessageCacheStore {
  MessageCacheStore({Future<Database> Function()? openDatabaseForTest})
      : _openDatabaseForTest = openDatabaseForTest;

  final Future<Database> Function()? _openDatabaseForTest;
  Database? _db;

  /// Android CursorWindow 约 2MB；单行须远小于此，且不能一次扫出全部 payload。
  static const maxPayloadChars = 600000;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    _db = _openDatabaseForTest != null
        ? await _openDatabaseForTest()
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
    final ids = await db.query(
      'messages',
      columns: ['message_id'],
      where: 'user_id = ? AND conversation_id = ?',
      whereArgs: [userId, conversationId],
      orderBy: 'created_at ASC',
    );
    final list = <ChatMessage>[];
    final dropIds = <String>[];
    for (final idRow in ids) {
      final messageId = idRow['message_id'] as String;
      try {
        final rows = await db.query(
          'messages',
          columns: ['payload'],
          where: 'user_id = ? AND conversation_id = ? AND message_id = ?',
          whereArgs: [userId, conversationId, messageId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final raw = rows.first['payload']! as String;
        if (raw.length > maxPayloadChars) {
          dropIds.add(messageId);
          continue;
        }
        final json = jsonDecode(raw) as Map<String, dynamic>;
        list.add(ChatMessage.fromJson(json));
      } catch (_) {
        dropIds.add(messageId);
      }
    }
    if (dropIds.isNotEmpty) {
      await _deleteMessages(userId, conversationId, dropIds);
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
        final payload = encodePayload(m);
        if (payload == null) continue;
        batch.insert(
          'messages',
          {
            'user_id': userId,
            'conversation_id': conversationId,
            'message_id': m.id,
            'payload': payload,
            'created_at': m.createdAt.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 压到 CursorWindow 安全范围内：去掉 inline 预览，必要时丢掉已解密消息的密文。
  static String? encodePayload(ChatMessage message) {
    var encoded = jsonEncode(message.toJson());
    if (encoded.length <= maxPayloadChars) return encoded;

    final slimPt = MediaLocalCache.stripInlineMediaBytes(message.plaintext);
    var compact = message;
    if (slimPt != null && slimPt != message.plaintext) {
      compact = message.copyWith(plaintext: slimPt);
      encoded = jsonEncode(compact.toJson());
      if (encoded.length <= maxPayloadChars) return encoded;
    }

    final pt = compact.plaintext;
    if (pt != null &&
        pt.isNotEmpty &&
        !ChatMessage.isDecryptPlaceholder(pt) &&
        !ChatMessage.isDecryptFailure(pt) &&
        compact.ciphertext.isNotEmpty) {
      compact = compact.copyWith(ciphertext: '');
      encoded = jsonEncode(compact.toJson());
      if (encoded.length <= maxPayloadChars) return encoded;
    }
    return null;
  }

  Future<void> _deleteMessages(
    String userId,
    String conversationId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) return;
    final db = await _database();
    final placeholders = List.filled(messageIds.length, '?').join(',');
    await db.delete(
      'messages',
      where:
          'user_id = ? AND conversation_id = ? AND message_id IN ($placeholders)',
      whereArgs: [userId, conversationId, ...messageIds],
    );
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
