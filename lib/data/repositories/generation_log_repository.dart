import '../../domain/generation/generation_log.dart';
import '../database/database_helper.dart';

class GenerationLogRepository {
  Future<GenerationLog?> getByMessageId(String messageId) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'generation_logs',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return GenerationLog.fromMap(maps.first);
  }

  Future<void> insert(GenerationLog log) async {
    final db = await DatabaseHelper.database;
    await db.insert('generation_logs', log.toMap());
  }

  Future<void> deleteByMessageId(String messageId) async {
    final db = await DatabaseHelper.database;
    await db.delete(
      'generation_logs',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }
}
