import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:peipal/data/database/database_helper.dart';
import 'package:peipal/data/database/database_path.dart';
import 'package:peipal/data/repositories/message_repository.dart';
import 'package:peipal/domain/models/document_parse_info.dart';

void main() {
  test(
    'v11 document rows survive v12 upgrade and persist resumable task metadata',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('document_migration_');
      databasesPathOverride = () async => dir.path;
      final old = await openDatabase(
        '${dir.path}/medhistory.db',
        version: 11,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE patients (id TEXT PRIMARY KEY, updated_at TEXT)',
          );
          await db.execute('''CREATE TABLE messages (
        id TEXT PRIMARY KEY, patient_id TEXT, sender TEXT, msg_type TEXT, content TEXT,
        file_paths TEXT, file_sizes TEXT, duration_ms INTEGER, page_count INTEGER,
        transcribed_text TEXT, extracted_text TEXT, record_json TEXT, template_id TEXT,
        record_meta TEXT, created_at TEXT)''');
          await db.insert('messages', {
            'id': 'old',
            'patient_id': 'p',
            'sender': 'user',
            'msg_type': 'document',
            'content': 'old.pdf',
            'file_paths': '["/old.pdf"]',
            'extracted_text': '旧内容',
            'created_at': DateTime.now().toIso8601String(),
          });
        },
      );
      await old.close();
      final db = await DatabaseHelper.database;
      try {
        expect(await db.getVersion(), 12);
        final repo = MessageRepository();
        final original = (await repo.getById('old'))!;
        expect(original.usableDocumentText, '旧内容');
        await repo.update(
          original.copyWith(
            documentParse: const DocumentParseInfo(
              status: DocumentParseStatus.running,
              attemptId: 'a',
              remoteTaskId: 'task',
              hasResult: true,
            ),
          ),
        );
        final pending = await repo.getInterruptedDocuments();
        expect(pending.single.documentParse!.remoteTaskId, 'task');
        expect(pending.single.usableDocumentText, '旧内容');
      } finally {
        await db.close();
        databasesPathOverride = null;
        await dir.delete(recursive: true);
      }
    },
  );
}
