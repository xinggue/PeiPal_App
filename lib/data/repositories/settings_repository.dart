import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

class SettingsRepository {
  Future<String?> get(String key) async {
    final db = await DatabaseHelper.database;
    final maps =
        await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> set(String key, String value) async {
    final db = await DatabaseHelper.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String key) async {
    final db = await DatabaseHelper.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
