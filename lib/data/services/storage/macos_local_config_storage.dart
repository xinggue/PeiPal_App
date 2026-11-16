import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';

/// Storage adapter for configuration consumers. Values are plain
/// text in the app's SQLite database; none of these operations use Keychain.
class MacosLocalConfigStorage extends FlutterSecureStorage {
  MacosLocalConfigStorage({Future<Database> Function()? database})
    : _database = database ?? (() => DatabaseHelper.database);

  final Future<Database> Function() _database;

  String _prefix(MacOsOptions? options) {
    final scope = (options ?? mOptions).toMap();
    final identity = jsonEncode([scope['accountName'], scope['groupId']]);
    return 'macos_config.v1.${base64Url.encode(utf8.encode(identity))}.';
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final db = await _database();
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['${_prefix(mOptions)}$key'],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      await delete(key: key, mOptions: mOptions);
      return;
    }
    final db = await _database();
    await db.insert('settings', {
      'key': '${_prefix(mOptions)}$key',
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final db = await _database();
    await db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: ['${_prefix(mOptions)}$key'],
    );
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => await read(key: key, mOptions: mOptions) != null;

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final db = await _database();
    final prefix = _prefix(mOptions);
    final rows = await db.query(
      'settings',
      where: 'substr(key, 1, ?) = ?',
      whereArgs: [prefix.length, prefix],
    );
    return {
      for (final row in rows)
        (row['key'] as String).substring(prefix.length): row['value'] as String,
    };
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final db = await _database();
    final prefix = _prefix(mOptions);
    await db.delete(
      'settings',
      where: 'substr(key, 1, ?) = ?',
      whereArgs: [prefix.length, prefix],
    );
  }
}
