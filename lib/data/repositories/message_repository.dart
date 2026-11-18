import 'package:flutter/foundation.dart';

import '../../domain/generation/generation_log.dart';
import '../../domain/models/message.dart';
import '../../domain/models/document_parse_info.dart';
import '../database/database_helper.dart';

class MessageRepository {
  List<Message> _safeMapRows(List<Map<String, dynamic>> rows) {
    final result = <Message>[];
    for (final row in rows) {
      try {
        result.add(Message.fromMap(row));
      } catch (e, st) {
        debugPrint('跳过损坏的消息行 (${row['id']}): $e\n$st');
      }
    }
    return result;
  }

  Future<List<Message>> getInterruptedDocuments() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('messages',
        where: "msg_type = 'document' AND document_parse IS NOT NULL");
    return _safeMapRows(rows)
        .where((m) => m.documentParse?.status == DocumentParseStatus.running)
        .toList();
  }

  /// 用于 UI 聊天瀑布流渲染（倒序展示，支持分页 limit/offset）。
  Future<List<Message>> getByPatient(
    String patientId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'messages',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return _safeMapRows(maps);
  }

  /// 用于文书管理页：无截断获取该会话下的全部已生成文书记录（倒序）。
  Future<List<Message>> getAllRecordsByPatient(String patientId) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'messages',
      where: "patient_id = ? AND msg_type = 'generatedRecord'",
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
    );
    return _safeMapRows(maps);
  }

  /// 用于临床病历生成与 Dry Run：无截断全量获取，且严格按时间正序排列。
  Future<List<Message>> getAllChronological(String patientId) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'messages',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at ASC',
    );
    return _safeMapRows(maps);
  }

  Future<Message?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query('messages', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Message.fromMap(maps.first);
  }

  Future<int> getCountByPatient(String patientId) async {
    final db = await DatabaseHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM messages WHERE patient_id = ?',
      [patientId],
    );
    return result.first['count'] as int;
  }

  Future<Message?> getLastByPatient(String patientId) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'messages',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Message.fromMap(maps.first);
  }

  Future<void> _touchPatient(dynamic dbOrTxn, String patientId) async {
    final now = DateTime.now().toIso8601String();
    await dbOrTxn.update(
      'patients',
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [patientId],
    );
  }

  Future<void> insert(Message message) async {
    final db = await DatabaseHelper.database;
    await db.transaction((txn) async {
      await txn.insert('messages', message.toMap());
      await _touchPatient(txn, message.patientId);
    });
  }

  /// 原子入库：生成病历消息与对应的全量审计日志在同一事务内完成，保证数据完整性。
  Future<void> insertGeneratedAtomic(Message message, GenerationLog log) async {
    final db = await DatabaseHelper.database;
    await db.transaction((txn) async {
      await txn.insert('messages', message.toMap());
      await txn.insert('generation_logs', log.toMap());
      await _touchPatient(txn, message.patientId);
    });
  }

  Future<void> update(Message message) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  /// 仅局部更新转写/识别文本列，避免异步耗时期间整行覆盖并发改动。
  Future<void> updateTextColumns(
    String id, {
    String? transcribedText,
    String? extractedText,
  }) async {
    final values = <String, Object?>{
      'transcribed_text': ?transcribedText,
      'extracted_text': ?extractedText,
    };
    if (values.isEmpty) return;
    final db = await DatabaseHelper.database;
    await db.update(
      'messages',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
}
