import 'package:sqflite/sqflite.dart';
import '../../domain/models/content_template.dart';
import '../database/database_helper.dart';

class ContentTemplateRepository {
  Future<List<ContentTemplate>> getAll() async {
    final db = await DatabaseHelper.database;
    final maps =
        await db.query('content_templates', orderBy: 'updated_at DESC');
    return maps.map((m) => ContentTemplate.fromMap(m)).toList();
  }

  Future<List<ContentTemplate>> getByStructure(String structureTemplateId) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'content_templates',
      where: 'structure_template_id = ?',
      whereArgs: [structureTemplateId],
      orderBy: 'updated_at DESC',
    );
    return maps.map((m) => ContentTemplate.fromMap(m)).toList();
  }

  Future<ContentTemplate?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final maps =
        await db.query('content_templates', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ContentTemplate.fromMap(maps.first);
  }

  Future<void> insert(ContentTemplate ct) async {
    final db = await DatabaseHelper.database;
    await db.insert(
      'content_templates',
      ct.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(ContentTemplate ct) async {
    final db = await DatabaseHelper.database;
    await db.update('content_templates', ct.toMap(),
        where: 'id = ?', whereArgs: [ct.id]);
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete('content_templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByStructure(String structureTemplateId) async {
    final db = await DatabaseHelper.database;
    await db.delete('content_templates',
        where: 'structure_template_id = ?',
        whereArgs: [structureTemplateId]);
  }
}
