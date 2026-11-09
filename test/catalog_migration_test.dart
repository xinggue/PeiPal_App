import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peipal/data/database/database_helper.dart';
import 'package:peipal/domain/models/catalog_definition.dart';

void main() {
  test('migrates favorite_diagnoses and legacy tags into generic catalogs',
      () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = p.join(await getDatabasesPath(), 'medhistory.db');
    await databaseFactory.deleteDatabase(dbPath);

    // Build a minimal v10 database containing the old diagnosis tables.
    final oldDb = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE favorite_diagnoses (
              id TEXT PRIMARY KEY,
              code TEXT NOT NULL,
              name TEXT NOT NULL,
              version TEXT NOT NULL DEFAULT '',
              note TEXT NOT NULL DEFAULT '',
              tags TEXT NOT NULL DEFAULT '[]',
              catalog_type TEXT NOT NULL DEFAULT 'diagnosis',
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    final now = DateTime.now().toIso8601String();
    await oldDb.insert('favorite_diagnoses', {
      'id': 'd1',
      'code': 'I10',
      'name': '高血压',
      'version': '医保2.0',
      'note': '',
      'tags': '["心内科"]',
      'catalog_type': 'diagnosis',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
    });
    await oldDb.insert('favorite_diagnoses', {
      'id': 'p1',
      'code': '36.06',
      'name': '冠脉支架置入',
      'version': '',
      'note': '',
      'tags': '["心内介入"]',
      'catalog_type': 'procedure',
      'sort_order': 1,
      'created_at': now,
      'updated_at': now,
    });
    await oldDb.insert('settings', {
      'key': 'diagnosis_tags',
      'value': '["心内科","门诊高频"]',
    });
    await oldDb.insert('settings', {
      'key': 'procedure_tags',
      'value': '["心内介入"]',
    });
    await oldDb.close();

    // Trigger the v11 upgrade.
    final db = await DatabaseHelper.database;

    final catalogs = await db.query('catalogs', orderBy: 'sort_order ASC');
    expect(catalogs.map((c) => c['id']), containsAll(['diagnosis', 'procedure']));

    final entries = await db.query('catalog_entries', orderBy: 'sort_order ASC');
    expect(entries, hasLength(2));
    expect(entries.first['name'], '高血压');
    expect(entries.first['catalog_type'], 'diagnosis');
    expect(entries.last['catalog_type'], 'procedure');

    final tags = await db.query('catalog_tags');
    final tagValues = tags.map((t) => t['tag']).toSet();
    expect(tagValues, containsAll(['心内科', '门诊高频', '心内介入']));

    await DatabaseHelper.deleteDatabase();
  });

  test('parses bundled_sqlite source kind stored in the database', () {
    final def = CatalogDefinition.fromMap({
      'id': 'diagnosis',
      'name': '诊断库',
      'description': '',
      'source_kind': 'bundled_sqlite',
      'source_asset': 'assets/data/icd_knowledge.db',
      'icon': 'diagnosis',
      'color': 0,
      'searchable': 1,
      'is_enabled': 1,
      'sort_order': 0,
      'is_system': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(def.sourceKind, CatalogSourceKind.bundledSqlite);
    expect(def.hasBundledSource, isTrue);

    final back = CatalogDefinition.fromMap(def.toMap());
    expect(back.sourceKind, CatalogSourceKind.bundledSqlite);
  });
}
