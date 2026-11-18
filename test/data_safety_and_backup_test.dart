import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peipal/data/database/database_helper.dart';
import 'package:peipal/data/database/database_path.dart';
import 'package:peipal/data/repositories/content_template_repository.dart';
import 'package:peipal/data/repositories/message_repository.dart';
import 'package:peipal/data/repositories/patient_repository.dart';
import 'package:peipal/data/repositories/settings_repository.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/data/services/backup/session_backup_service.dart';
import 'package:peipal/data/services/sample_data_service.dart';
import 'package:peipal/domain/generation/generation_log.dart';
import 'package:peipal/domain/models/message.dart';
import 'package:peipal/domain/models/patient.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/presentation/widgets/backup/session_backup_cards.dart';
import 'package:peipal/providers/providers.dart';

class _StubFileSelector extends FileSelectorPlatform {
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async =>
      null;
}

class _FakeSessionBackupService extends SessionBackupService {
  Completer<void>? gate;

  @override
  Future<SessionDataSummary> getLocalSummary() async => const SessionDataSummary(
        patientCount: 2,
        messageCount: 10,
        recordCount: 3,
        mediaFileCount: 4,
        mediaBytes: 2048,
      );

  @override
  Future<SessionBackupExportResult> exportToZipFile(
    File targetZipFile, {
    String? password,
    void Function(SessionBackupProgress progress)? onProgress,
  }) async {
    onProgress?.call(const SessionBackupProgress(
      message: '正在打包并加密（1 / 1）…',
      current: 1,
      total: 1,
    ));
    if (gate != null) {
      await gate!.future;
    }
    return SessionBackupExportResult(
      file: targetZipFile,
      patientCount: 2,
      messageCount: 10,
      recordCount: 3,
      logCount: 1,
      mediaFileCount: 4,
      zipBytes: 1024,
      encrypted: password != null && password.isNotEmpty,
    );
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempRoot;
  late Directory dbDir;
  late Directory mediaDir;

  setUp(() async {
    await DatabaseHelper.closeDatabase();
    tempRoot = await Directory.systemTemp.createTemp('peipal_data_safety_');
    dbDir = Directory(p.join(tempRoot.path, 'db'));
    mediaDir = Directory(p.join(tempRoot.path, 'media'));
    await dbDir.create(recursive: true);
    await mediaDir.create(recursive: true);
    databasesPathOverride = () async => dbDir.path;
    sessionBackupMediaRootOverride = () async => mediaDir.path;
  });

  tearDown(() async {
    await DatabaseHelper.closeDatabase();
    databasesPathOverride = null;
    sessionBackupMediaRootOverride = null;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('DatabaseHelper safety', () {
    test('blocks downgrade without overwriting user_version and allows retry after failure', () async {
      final dbPath = p.join(dbDir.path, 'medhistory.db');
      final futureDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: DatabaseHelper.currentVersion + 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE patients (id TEXT PRIMARY KEY)');
          },
        ),
      );
      await futureDb.close();

      await expectLater(
        DatabaseHelper.database,
        throwsA(isA<DatabaseDowngradeException>()),
      );

      // Verify user_version on disk remained intact (was NOT silently lowered to 12).
      final check = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      expect(await check.getVersion(), DatabaseHelper.currentVersion + 1);
      await check.close();

      // Verify _initFuture was reset on error so replacing with a valid DB succeeds cleanly.
      await File(dbPath).delete();
      final recovered = await DatabaseHelper.database;
      expect(await recovered.getVersion(), DatabaseHelper.currentVersion);
    });

    test('snapshots v11 database before v12 upgrade and tolerates pre-existing document_parse column', () async {
      final dbPath = p.join(dbDir.path, 'medhistory.db');
      final oldDb = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (db, _) async {
            await db.execute(
                'CREATE TABLE patients (id TEXT PRIMARY KEY, updated_at TEXT)');
            await db.execute('''
              CREATE TABLE messages (
                id TEXT PRIMARY KEY, patient_id TEXT, sender TEXT, msg_type TEXT, content TEXT,
                file_paths TEXT, file_sizes TEXT, duration_ms INTEGER, page_count INTEGER,
                transcribed_text TEXT, extracted_text TEXT, document_parse TEXT,
                record_json TEXT, template_id TEXT, record_meta TEXT, created_at TEXT
              )
            ''');
          },
        ),
      );
      await oldDb.close();

      final db = await DatabaseHelper.database;
      expect(await db.getVersion(), DatabaseHelper.currentVersion);
      expect(await File('$dbPath.pre_v11.bak').exists(), isTrue);
    });
  });

  group('Repository resilience & untruncated records', () {
    test('getAllRecordsByPatient returns >100 generated records and skips malformed rows', () async {
      final db = await DatabaseHelper.database;
      final patientRepo = PatientRepository();
      final messageRepo = MessageRepository();

      final patient = Patient(name: '测试患者');
      await patientRepo.insert(patient);

      final baseTime = DateTime(2026, 1, 1);
      for (var i = 0; i < 115; i++) {
        await messageRepo.insert(Message(
          id: 'rec_$i',
          patientId: patient.id,
          sender: MessageSender.system,
          type: MessageType.generatedRecord,
          recordJson: '{"主诉": "第$i条"}',
          createdAt: baseTime.add(Duration(minutes: i)),
        ));
      }

      // Inject one corrupted row directly into SQLite
      await db.insert('messages', {
        'id': 'bad_row',
        'patient_id': patient.id,
        'sender': 'invalid_sender',
        'msg_type': 'generatedRecord',
        'created_at': 'not_a_date',
      });

      final paged = await messageRepo.getByPatient(patient.id, limit: 100);
      expect(paged.length, 99);

      final secondPage =
          await messageRepo.getByPatient(patient.id, limit: 100, offset: 100);
      expect(secondPage.length, 16);

      final allRecords = await messageRepo.getAllRecordsByPatient(patient.id);
      expect(allRecords.length, 115);

      await patientRepo.delete(patient.id);
      expect(await patientRepo.getById(patient.id), isNull);
      expect(await messageRepo.getCountByPatient(patient.id), 0);
    });
  });

  group('SampleDataService protection', () {
    test('preserves sample patient when user added records and version changes', () async {
      final patientRepo = PatientRepository();
      final messageRepo = MessageRepository();
      final templateRepo = TemplateRepository();
      final contentTemplateRepo = ContentTemplateRepository();
      final settingsRepo = SettingsRepository();

      final svc = SampleDataService(
        patientRepo: patientRepo,
        messageRepo: messageRepo,
        templateRepo: templateRepo,
        contentTemplateRepo: contentTemplateRepo,
        settingsRepo: settingsRepo,
        seedMedia: false,
      );

      await svc.ensureSampleData();
      // User adds a generated record under sample patient
      await messageRepo.insert(Message(
        id: 'user_generated_in_sample',
        patientId: SampleDataService.samplePatientId,
        sender: MessageSender.system,
        type: MessageType.generatedRecord,
        recordJson: '{"主诉": "真实记录"}',
      ));

      // Simulate an app update bumping sample_data_version
      await settingsRepo.set(SampleDataService.keySampleVersion, '6');
      await svc.ensureSampleData();

      final preserved = await messageRepo.getById('user_generated_in_sample');
      expect(preserved, isNotNull);
    });
  });

  group('SessionBackupService ZIP export and restore', () {
    test('exports only session data & media (no configs/templates) and restores across devices with path rewrite', () async {
      final patientRepo = PatientRepository();
      final messageRepo = MessageRepository();
      final templateRepo = TemplateRepository();
      final settingsRepo = SettingsRepository();

      // Seed config/template (should NOT be wiped or overwritten on data restore)
      await templateRepo.insert(Template(
        id: 'tpl_local',
        name: '本地模板',
        slots: const [TemplateSlot(key: '主诉', label: '主诉', type: SlotType.text)],
      ));
      await settingsRepo.set('font_scale', '1.25');

      // Seed patient + media + message + log
      final patient = Patient(id: 'p1', name: '张三');
      await patientRepo.insert(patient);

      final photoFile = File(p.join(mediaDir.path, 'photos', 'p1', 'm1', 'page_001.jpg'));
      await photoFile.parent.create(recursive: true);
      await photoFile.writeAsBytes([1, 2, 3, 4, 5]);

      final msg = Message(
        id: 'm1',
        patientId: 'p1',
        sender: MessageSender.user,
        type: MessageType.photo,
        filePaths: [photoFile.path],
        fileSizes: const [5],
      );
      final rec = Message(
        id: 'm2',
        patientId: 'p1',
        sender: MessageSender.system,
        type: MessageType.generatedRecord,
        recordJson: '{"主诉":"咳嗽3天"}',
        templateId: 'tpl_local',
      );
      await messageRepo.insert(msg);
      await messageRepo.insertGeneratedAtomic(
        rec,
        GenerationLog(
          id: 'log1',
          messageId: 'm2',
          patientId: 'p1',
          templateId: 'tpl_local',
          templateName: '本地模板',
          status: 'success',
          totalDurationMs: 500,
          stages: const [],
          createdAt: DateTime(2026, 11, 18),
        ),
      );

      final svc = SessionBackupService();
      final summary = await svc.getLocalSummary();
      expect(summary.patientCount, 1);
      expect(summary.messageCount, 2);
      expect(summary.recordCount, 1);
      expect(summary.mediaFileCount, 1);

      final zipOut = File(p.join(tempRoot.path, 'backup.zip'));
      final exportResult = await svc.exportToZipFile(zipOut);
      expect(exportResult.patientCount, 1);
      expect(exportResult.mediaFileCount, 1);

      // Verify ZIP contains data & media, NOT templates/settings
      final decodedArchive = ZipDecoder().decodeBytes(await zipOut.readAsBytes());
      final entryNames = decodedArchive.files.map((f) => f.name).toSet();
      expect(entryNames, contains('manifest.json'));
      expect(entryNames, contains('data.json'));
      expect(entryNames, contains('media/photos/p1/m1/page_001.jpg'));
      final dataJsonStr = utf8.decode(
        decodedArchive.files.firstWhere((f) => f.name == 'data.json').readBytes()!,
      );
      expect(dataJsonStr.contains('tpl_local'), isTrue); // only message.template_id ref
      expect(dataJsonStr.contains('font_scale'), isFalse);

      // Switch to a fresh "new device" DB & media root
      await DatabaseHelper.closeDatabase();
      final dbDir2 = Directory(p.join(tempRoot.path, 'db2'));
      final mediaDir2 = Directory(p.join(tempRoot.path, 'media2'));
      await dbDir2.create();
      await mediaDir2.create();
      databasesPathOverride = () async => dbDir2.path;
      sessionBackupMediaRootOverride = () async => mediaDir2.path;

      // Seed an existing local template & another patient on the new device
      await TemplateRepository().insert(Template(
        id: 'tpl_new_device',
        name: '新设备模板',
        slots: const [TemplateSlot(key: '诊断', label: '诊断', type: SlotType.text)],
      ));
      await PatientRepository().insert(Patient(id: 'p_existing', name: '李四'));

      final preview = await svc.inspectZipFile(zipOut);
      expect(preview.patientCount, 1);
      expect(preview.messageCount, 2);
      expect(preview.recordCount, 1);
      expect(preview.conflictPatientCount, 0);

      // Merge restore preserves p_existing & tpl_new_device
      final mergeRes = await svc.restoreFromZipFile(zipOut, mode: SessionRestoreMode.merge);
      expect(mergeRes.restoredPatients, 1);
      expect(mergeRes.restoredMessages, 2);
      expect(mergeRes.restoredLogs, 1);
      expect(mergeRes.restoredMediaFiles, 1);

      final allPatients = await PatientRepository().getAll();
      expect(allPatients.map((p) => p.id).toSet(), {'p1', 'p_existing'});
      expect(await TemplateRepository().getById('tpl_new_device'), isNotNull);

      final restoredPhotoMsg = (await MessageRepository().getById('m1'))!;
      final expectedNewPhotoPath =
          p.join(mediaDir2.path, 'photos', 'p1', 'm1', 'page_001.jpg');
      expect(restoredPhotoMsg.filePaths.single, expectedNewPhotoPath);
      expect(await File(expectedNewPhotoPath).readAsBytes(), [1, 2, 3, 4, 5]);

      // Replace restore wipes p_existing but STILL preserves tpl_new_device and creates pre_restore snapshot
      final replaceRes = await svc.restoreFromZipFile(zipOut, mode: SessionRestoreMode.replace);
      expect(replaceRes.restoredPatients, 1);
      expect((await PatientRepository().getAll()).map((p) => p.id), ['p1']);
      expect(await TemplateRepository().getById('tpl_new_device'), isNotNull);
      expect(
        await File(p.join(dbDir2.path, 'medhistory.db.pre_restore.bak')).exists(),
        isTrue,
      );
    });

    test('rejects invalid ZIP and ignores Zip Slip entries', () async {
      final svc = SessionBackupService();
      final badZip = File(p.join(tempRoot.path, 'bad.zip'));
      await badZip.writeAsString('not a zip');
      await expectLater(
        svc.inspectZipFile(badZip),
        throwsA(isA<FormatException>()),
      );

      // Build a ZIP with a malicious ../ traversal media entry
      final archive = Archive()
        ..addFile(ArchiveFile.bytes(
          'manifest.json',
          utf8.encode(jsonEncode({'format': 'peipal_data_backup', 'version': 1})),
        ))
        ..addFile(ArchiveFile.bytes(
          'data.json',
          utf8.encode(jsonEncode({'patients': [], 'messages': [], 'generationLogs': []})),
        ))
        ..addFile(ArchiveFile.bytes('media/../../escaped.txt', [9, 9, 9]));
      final slipZip = File(p.join(tempRoot.path, 'slip.zip'));
      await slipZip.writeAsBytes(ZipEncoder().encode(archive));

      final res = await svc.restoreFromZipFile(slipZip, mode: SessionRestoreMode.merge);
      expect(res.restoredMediaFiles, 0);
      expect(await File(p.join(tempRoot.path, 'escaped.txt')).exists(), isFalse);
    });

    test('supports password-encrypted ZIP export and validates password on restore', () async {
      final patientRepo = PatientRepository();
      final messageRepo = MessageRepository();

      await patientRepo.insert(Patient(id: 'p_enc', name: '加密会话'));
      final docFile = File(p.join(mediaDir.path, 'documents', 'p_enc', 'm_doc_检查报告.pdf'));
      await docFile.parent.create(recursive: true);
      await docFile.writeAsBytes([10, 20, 30, 40]);

      await messageRepo.insert(Message(
        id: 'm_enc',
        patientId: 'p_enc',
        sender: MessageSender.user,
        type: MessageType.document,
        content: '检查报告.pdf',
        filePaths: [docFile.path],
        fileSizes: const [4],
      ));

      final svc = SessionBackupService();
      final encZip = File(p.join(tempRoot.path, 'encrypted_backup.zip'));
      final exportProgressEvents = <SessionBackupProgress>[];
      final exportRes = await svc.exportToZipFile(
        encZip,
        password: 'Secret#123',
        onProgress: exportProgressEvents.add,
      );
      expect(exportRes.encrypted, isTrue);
      expect(exportProgressEvents.any((e) => e.total == 1 && e.current == 1), isTrue);

      // Switch to fresh device DB
      await DatabaseHelper.closeDatabase();
      final dbDir2 = Directory(p.join(tempRoot.path, 'db_enc_2'));
      final mediaDir2 = Directory(p.join(tempRoot.path, 'media_enc_2'));
      await dbDir2.create();
      await mediaDir2.create();
      databasesPathOverride = () async => dbDir2.path;
      sessionBackupMediaRootOverride = () async => mediaDir2.path;

      // 1. Missing password throws BackupPasswordRequiredException
      await expectLater(
        svc.inspectZipFile(encZip),
        throwsA(isA<BackupPasswordRequiredException>()),
      );

      // 2. Wrong password throws BackupWrongPasswordException
      await expectLater(
        svc.inspectZipFile(encZip, password: 'wrong'),
        throwsA(isA<BackupWrongPasswordException>()),
      );

      // 3. Correct password previews and restores cleanly with progress updates
      final preview = await svc.inspectZipFile(encZip, password: 'Secret#123');
      expect(preview.patientCount, 1);
      expect(preview.mediaFileCount, 1);

      final restoreProgressEvents = <SessionBackupProgress>[];
      final restoreRes = await svc.restoreFromZipFile(
        encZip,
        mode: SessionRestoreMode.merge,
        password: 'Secret#123',
        onProgress: restoreProgressEvents.add,
      );
      expect(restoreRes.restoredPatients, 1);
      expect(restoreRes.restoredMessages, 1);
      expect(restoreRes.restoredMediaFiles, 1);
      expect(restoreProgressEvents.any((e) => e.total == 1 && e.current == 1), isTrue);

      final restoredDoc = (await MessageRepository().getById('m_enc'))!;
      final expectedPath =
          p.join(mediaDir2.path, 'documents', 'p_enc', 'm_doc_检查报告.pdf');
      expect(restoredDoc.filePaths.single, expectedPath);
      expect(await File(expectedPath).readAsBytes(), [10, 20, 30, 40]);
    });

    testWidgets('SessionExportCard password confirm dialog and progress modal run cleanly without dependents assertion', (tester) async {
      final originalSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _StubFileSelector();
      addTearDown(() => FileSelectorPlatform.instance = originalSelector);

      final fakeSvc = _FakeSessionBackupService()..gate = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionBackupServiceProvider.overrideWithValue(fakeSvc),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SessionExportCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter optional password
      await tester.enterText(find.byType(TextField).first, 'pass1234');
      await tester.tap(find.text('确认备份会话'));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('确认备份密码'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'pass1234');
      await tester.tap(find.text('确认'));

      // Allow real Directory.systemTemp.createTemp I/O to finish, then pump UI frames
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('正在打包并加密'), findsOneWidget);
      expect(tester.takeException(), isNull);

      fakeSvc.gate!.complete();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      // Let AppToast's 2.2s auto-dismiss timer finish cleanly
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
