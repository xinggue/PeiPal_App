import 'package:sqflite/sqflite.dart';

import '../../domain/models/catalog_definition.dart';
import '../database/database_helper.dart';

class CatalogRepository {
  static const String table = 'catalogs';

  Future<List<CatalogDefinition>> getAll({bool includeDisabled = true}) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      table,
      where: includeDisabled ? null : 'is_enabled = 1',
      orderBy: 'sort_order ASC, name ASC',
    );
    return maps.map((m) => CatalogDefinition.fromMap(m)).toList();
  }

  Future<CatalogDefinition?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(table, where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return CatalogDefinition.fromMap(maps.first);
  }

  Future<void> insert(CatalogDefinition catalog) async {
    final db = await DatabaseHelper.database;
    await db.insert(
      table,
      catalog.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(CatalogDefinition catalog) async {
    final db = await DatabaseHelper.database;
    await db.update(
      table,
      catalog.toMap(),
      where: 'id = ?',
      whereArgs: [catalog.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}
