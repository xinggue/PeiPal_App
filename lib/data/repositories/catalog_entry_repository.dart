import 'package:sqflite/sqflite.dart';

import '../../domain/models/catalog_entry.dart';
import '../database/database_helper.dart';

/// Generic CRUD for user-managed catalog entries (诊断、手术、中医、病理、法律…).
class CatalogEntryRepository {
  static const String table = 'catalog_entries';

  Future<List<CatalogEntry>> getAll({String? catalogType}) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      table,
      where: catalogType == null ? null : 'catalog_type = ?',
      whereArgs: catalogType == null ? null : [catalogType],
      orderBy: 'sort_order ASC, updated_at DESC',
    );
    return maps.map((m) => CatalogEntry.fromMap(m)).toList();
  }

  Future<CatalogEntry?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return CatalogEntry.fromMap(maps.first);
  }

  Future<CatalogEntry?> findByCodeAndName(
    String code,
    String name, {
    String catalogType = 'diagnosis',
  }) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      table,
      where: 'code = ? AND name = ? AND catalog_type = ?',
      whereArgs: [code, name, catalogType],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return CatalogEntry.fromMap(maps.first);
  }

  Future<List<CatalogEntry>> search(
    String catalogType,
    String query, {
    int limit = 50,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final db = await DatabaseHelper.database;
    final like = '%$q%';
    final maps = await db.query(
      table,
      where:
          'catalog_type = ? AND (name LIKE ? OR code LIKE ? OR note LIKE ? OR tags LIKE ?)',
      whereArgs: [catalogType, like, like, like, like],
      orderBy: 'sort_order ASC, updated_at DESC',
      limit: limit,
    );
    return maps.map((m) => CatalogEntry.fromMap(m)).toList();
  }

  Future<List<CatalogEntry>> getPaged(
    String catalogType, {
    int offset = 0,
    int limit = 50,
  }) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      table,
      where: 'catalog_type = ?',
      whereArgs: [catalogType],
      orderBy: 'sort_order ASC, updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => CatalogEntry.fromMap(m)).toList();
  }

  Future<int> getTotalCount(String catalogType) async {
    final db = await DatabaseHelper.database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM $table WHERE catalog_type = ?',
      [catalogType],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> countByTag(String catalogType, String tag) async {
    final db = await DatabaseHelper.database;
    final res = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM $table WHERE catalog_type = ? AND tags LIKE ?",
      [catalogType, '%"$tag"%'],
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<void> insert(CatalogEntry entry) async {
    final db = await DatabaseHelper.database;
    await db.insert(
      table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> update(CatalogEntry entry) async {
    final db = await DatabaseHelper.database;
    await db.update(
      table,
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByCodeAndName(
    String code,
    String name, {
    String catalogType = 'diagnosis',
  }) async {
    final db = await DatabaseHelper.database;
    await db.delete(
      table,
      where: 'code = ? AND name = ? AND catalog_type = ?',
      whereArgs: [code, name, catalogType],
    );
  }

  Future<void> deleteByCatalog(String catalogType) async {
    final db = await DatabaseHelper.database;
    await db.delete(table, where: 'catalog_type = ?', whereArgs: [catalogType]);
  }
}
