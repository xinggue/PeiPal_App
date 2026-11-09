import 'package:uuid/uuid.dart';

import '../../domain/models/catalog_entry.dart';
import '../database/database_helper.dart';

const _uuid = Uuid();

class CatalogTagsRepository {
  static const String table = 'catalog_tags';

  Future<List<String>> getAll(String catalogType) async {
    final db = await DatabaseHelper.database;
    // One-time cleanup of placeholder tags inherited from very old versions.
    final placeholders = kLegacyPlaceholderTags.toList();
    final clauses = [
      "tag IN (${List.filled(placeholders.length, '?').join(',')})",
      "tag LIKE '分类%'",
      "tag LIKE '标签%'",
    ];
    await db.delete(
      table,
      where: 'catalog_type = ? AND (${clauses.join(' OR ')})',
      whereArgs: [catalogType, ...placeholders],
    );
    final maps = await db.query(
      table,
      columns: ['tag'],
      where: 'catalog_type = ?',
      whereArgs: [catalogType],
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return maps
        .map((m) => m['tag'] as String)
        .where((tag) => !isLegacyPlaceholderTag(tag))
        .toList();
  }

  Future<void> addTag(String catalogType, String tag) async {
    final t = tag.trim();
    if (t.isEmpty) return;
    final db = await DatabaseHelper.database;
    final existing = await db.query(
      table,
      columns: ['id'],
      where: 'catalog_type = ? AND tag = ?',
      whereArgs: [catalogType, t],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final now = DateTime.now().toIso8601String();
    await db.insert(table, {
      'id': _uuid.v4(),
      'catalog_type': catalogType,
      'tag': t,
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> renameTag(String catalogType, String oldTag, String newTag) async {
    final oldT = oldTag.trim();
    final newT = newTag.trim();
    if (oldT.isEmpty || newT.isEmpty || oldT == newT) return;
    final db = await DatabaseHelper.database;

    final existing = await db.query(
      table,
      columns: ['id'],
      where: 'catalog_type = ? AND tag = ?',
      whereArgs: [catalogType, newT],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.update(
        table,
        {'tag': newT, 'updated_at': DateTime.now().toIso8601String()},
        where: 'catalog_type = ? AND tag = ?',
        whereArgs: [catalogType, oldT],
      );
    } else {
      await db.delete(
        table,
        where: 'catalog_type = ? AND tag = ?',
        whereArgs: [catalogType, oldT],
      );
    }
  }

  Future<void> deleteTag(String catalogType, String tag) async {
    final db = await DatabaseHelper.database;
    await db.delete(
      table,
      where: 'catalog_type = ? AND tag = ?',
      whereArgs: [catalogType, tag],
    );
  }

  Future<void> deleteByCatalog(String catalogType) async {
    final db = await DatabaseHelper.database;
    await db.delete(table, where: 'catalog_type = ?', whereArgs: [catalogType]);
  }
}
