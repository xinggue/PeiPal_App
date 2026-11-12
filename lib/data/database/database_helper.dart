import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'database_path.dart';

class DatabaseHelper {
  static Database? _db;
  static Future<Database>? _initFuture;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _initFuture ??= _initDb();
    _db = await _initFuture!;
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await appDatabasesPath();
    final path = p.join(dbPath, 'medhistory.db');

    return openDatabase(
      path,
      version: 11,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE patients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        gender TEXT NOT NULL,
        age INTEGER,
        medical_record_number TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        extra_data TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        patient_id TEXT NOT NULL,
        sender TEXT NOT NULL,
        msg_type TEXT NOT NULL,
        content TEXT,
        file_paths TEXT,
        file_sizes TEXT,
        duration_ms INTEGER,
        page_count INTEGER,
        transcribed_text TEXT,
        extracted_text TEXT,
        record_json TEXT,
        template_id TEXT,
        record_meta TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        version TEXT NOT NULL,
        slots TEXT NOT NULL,
        example_values TEXT NOT NULL,
        pipeline TEXT NOT NULL DEFAULT '',
        typing_profiles TEXT NOT NULL DEFAULT '[]',
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

    await db.execute(
        'CREATE INDEX idx_messages_patient ON messages(patient_id, created_at)');

    await db.execute('''
      CREATE TABLE content_templates (
        id TEXT PRIMARY KEY,
        structure_template_id TEXT NOT NULL,
        name TEXT NOT NULL,
        global_guidance TEXT NOT NULL DEFAULT '',
        full_example TEXT NOT NULL DEFAULT '',
        slot_data TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (structure_template_id) REFERENCES templates(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_ct_structure ON content_templates(structure_template_id)');

    await _createCatalogTables(db);
    await _seedCatalogs(db);

    await db.execute('''
      CREATE TABLE generation_logs (
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        patient_id TEXT NOT NULL,
        template_id TEXT NOT NULL,
        template_name TEXT NOT NULL,
        model TEXT NOT NULL,
        status TEXT NOT NULL,
        total_duration_ms INTEGER NOT NULL,
        stages_json TEXT NOT NULL,
        issues_json TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_gen_logs_msg ON generation_logs(message_id)');
  }

  static Future<void> _createCatalogTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalogs (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        source_kind TEXT NOT NULL DEFAULT 'managed',
        source_asset TEXT NOT NULL DEFAULT '',
        icon TEXT NOT NULL DEFAULT '',
        color INTEGER NOT NULL DEFAULT 0,
        searchable INTEGER NOT NULL DEFAULT 0,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_system INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_entries (
        id TEXT PRIMARY KEY,
        catalog_type TEXT NOT NULL DEFAULT 'diagnosis',
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        version TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '[]',
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS catalog_tags (
        id TEXT PRIMARY KEY,
        catalog_type TEXT NOT NULL,
        tag TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_catalog_entries_order ON catalog_entries(catalog_type, sort_order, updated_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_catalog_entries_type ON catalog_entries(catalog_type)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_catalog_tags_unique ON catalog_tags(catalog_type, tag)');
  }

  static Future<void> _seedCatalogs(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    final seeds = <Map<String, Object>>[
      {
        'id': 'diagnosis',
        'name': '诊断库',
        'description': 'ICD-10 标准诊断词条',
        'source_kind': 'bundled_sqlite',
        'source_asset': 'assets/data/icd_knowledge.db',
        'icon': 'diagnosis',
        'color': 0,
        'searchable': 1,
        'is_enabled': 1,
        'sort_order': 0,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      },
      {
        'id': 'procedure',
        'name': '手术库',
        'description': '手术与操作词条',
        'source_kind': 'managed',
        'source_asset': '',
        'icon': 'procedure',
        'color': 0,
        'searchable': 0,
        'is_enabled': 1,
        'sort_order': 1,
        'is_system': 1,
        'created_at': now,
        'updated_at': now,
      },
    ];
    for (final seed in seeds) {
      await db.insert('catalogs', seed,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<void> _migrateLegacyTags(
    DatabaseExecutor db,
    String catalogType,
    String settingsKey,
  ) async {
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [settingsKey], limit: 1);
    if (rows.isEmpty) return;
    final raw = rows.first['value'] as String?;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final now = DateTime.now().toIso8601String();
      for (var i = 0; i < decoded.length; i++) {
        final tag = decoded[i].toString().trim();
        if (tag.isEmpty) continue;
        await db.insert(
          'catalog_tags',
          {
            'id': '$catalogType-tag-$i-${DateTime.now().microsecondsSinceEpoch}',
            'catalog_type': catalogType,
            'tag': tag,
            'sort_order': i,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    } catch (_) {}
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // Handled by v5 rewrite
    }
    if (oldV < 3) {
      await db.execute(
          "ALTER TABLE patients ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
    }
    if (oldV < 4) {
      await db.execute(
          "ALTER TABLE templates ADD COLUMN pipeline TEXT NOT NULL DEFAULT ''");
    }
    if (oldV < 5) {
      await db.execute(
          "ALTER TABLE templates ADD COLUMN typing_profiles TEXT NOT NULL DEFAULT '[]'");
      await db.execute('DROP TABLE IF EXISTS content_templates');
      await db.execute('''
        CREATE TABLE content_templates (
          id TEXT PRIMARY KEY,
          structure_template_id TEXT NOT NULL,
          name TEXT NOT NULL,
          global_guidance TEXT NOT NULL DEFAULT '',
          full_example TEXT NOT NULL DEFAULT '',
          slot_data TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (structure_template_id) REFERENCES templates(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_ct_structure ON content_templates(structure_template_id)');
    }
    if (oldV < 6) {
      await db.execute('''
        CREATE TABLE favorite_diagnoses (
          id TEXT PRIMARY KEY,
          code TEXT NOT NULL,
          name TEXT NOT NULL,
          version TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_fav_diag_order ON favorite_diagnoses(sort_order, updated_at DESC)');
    }
    if (oldV < 7) {
      await db.execute(
          "ALTER TABLE favorite_diagnoses ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'");
    }
    if (oldV < 8) {
      await db.execute(
          "ALTER TABLE messages ADD COLUMN record_meta TEXT");
      await db.execute('''
        CREATE TABLE generation_logs (
          id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          patient_id TEXT NOT NULL,
          template_id TEXT NOT NULL,
          template_name TEXT NOT NULL,
          model TEXT NOT NULL,
          status TEXT NOT NULL,
          total_duration_ms INTEGER NOT NULL,
          stages_json TEXT NOT NULL,
          issues_json TEXT NOT NULL,
          error_message TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_gen_logs_msg ON generation_logs(message_id)');
    }
    if (oldV < 9) {
      await db.execute(
          "ALTER TABLE favorite_diagnoses ADD COLUMN catalog_type TEXT NOT NULL DEFAULT 'diagnosis'");
      await db.execute(
          'CREATE INDEX idx_fav_diag_type ON favorite_diagnoses(catalog_type)');
    }
    if (oldV < 10) {
      await db.execute(
          "ALTER TABLE patients ADD COLUMN extra_data TEXT NOT NULL DEFAULT '{}'");
    }
    if (oldV < 11) {
      await _createCatalogTables(db);
      await _seedCatalogs(db);

      // Copy legacy favorite entries into the generic catalog table.
      final oldTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='favorite_diagnoses'");
      if (oldTable.isNotEmpty) {
        await db.execute('''
          INSERT OR IGNORE INTO catalog_entries
            (id, catalog_type, code, name, version, note, tags, sort_order, created_at, updated_at)
          SELECT
            id,
            CASE WHEN catalog_type IS NULL OR catalog_type = '' THEN 'diagnosis' ELSE catalog_type END,
            code,
            name,
            COALESCE(version, ''),
            COALESCE(note, ''),
            COALESCE(tags, '[]'),
            COALESCE(sort_order, 0),
            created_at,
            updated_at
          FROM favorite_diagnoses
        ''');
        await db.execute('DROP TABLE IF EXISTS favorite_diagnoses');
      }

      // Auto-register any legacy catalog types that were not built in.
      final distinctTypes = await db.rawQuery(
          'SELECT DISTINCT catalog_type FROM catalog_entries');
      final now = DateTime.now().toIso8601String();
      for (final row in distinctTypes) {
        final type = row['catalog_type']?.toString() ?? '';
        if (type.isEmpty) continue;
        await db.insert(
          'catalogs',
          {
            'id': type,
            'name': type,
            'description': '',
            'source_kind': 'managed',
            'source_asset': '',
            'icon': '',
            'color': 0,
            'searchable': 0,
            'is_enabled': 1,
            'sort_order': 100,
            'is_system': 0,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await _migrateLegacyTags(db, 'diagnosis', 'diagnosis_tags');
      await _migrateLegacyTags(db, 'procedure', 'procedure_tags');
    }
  }

  static Future<void> deleteDatabase() async {
    final dbPath = await appDatabasesPath();
    final path = p.join(dbPath, 'medhistory.db');
    await databaseFactory.deleteDatabase(path);
    _db = null;
  }
}
