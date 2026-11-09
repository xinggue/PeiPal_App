import '../../domain/generation/generation_log.dart';
import '../../domain/models/message.dart';
import '../database/database_helper.dart';

class MessageRepository {
  /// 用于 UI 聊天瀑布流渲染（倒序展示，限制近期 100 条）。
  Future<List<Message>> getByPatient(String patientId, {int limit = 100}) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'messages',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map((m) => Message.fromMap(m)).toList();
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
    return maps.map((m) => Message.fromMap(m)).toList();
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

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
}
