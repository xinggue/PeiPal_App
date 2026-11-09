import 'package:sqflite/sqflite.dart';
import '../../domain/models/template.dart';
import '../database/database_helper.dart';

class TemplateRepository {
  Future<List<Template>> getAll() async {
    final db = await DatabaseHelper.database;
    final maps = await db.query('templates', orderBy: 'updated_at DESC');
    return maps.map((m) => Template.fromMap(m)).toList();
  }

  Future<Template?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query('templates', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Template.fromMap(maps.first);
  }

  Future<void> insert(Template template) async {
    final db = await DatabaseHelper.database;
    await db.insert(
      'templates',
      template.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(Template template) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'templates',
      template.toMap(),
      where: 'id = ?',
      whereArgs: [template.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete('templates', where: 'id = ?', whereArgs: [id]);
  }
}
