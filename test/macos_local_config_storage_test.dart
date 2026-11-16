import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:peipal/data/database/macos_database_permissions.dart';
import 'package:peipal/data/services/hub/hub_service.dart';
import 'package:peipal/data/services/storage/macos_local_config_storage.dart';
import 'package:peipal/providers/providers.dart';
import 'package:peipal/providers/llm_providers_provider.dart';
import 'package:peipal/providers/asr_providers_provider.dart';
import 'package:peipal/providers/ocr_providers_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:peipal/data/services/backup/backup_service.dart';
import 'package:peipal/data/services/api/document_parser_config_store.dart';

import 'backup_service_test.dart'
    show
        InMemoryTemplateRepo,
        InMemoryContentTemplateRepo,
        InMemoryFavDiagRepo,
        InMemorySettingsRepo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late Database db;
  late MacosLocalConfigStorage storage;
  var keychainCalls = 0;

  setUp(() async {
    keychainCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            keychainCalls++;
            throw StateError('Local storage must never call Keychain');
          },
        );
    directory = await Directory.systemTemp.createTemp('peipal-config-test-');
    path = p.join(directory.path, 'config.db');
    db = await databaseFactoryFfi.openDatabase(path);
    await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    storage = MacosLocalConfigStorage(database: () async => db);
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
    expect(keychainCalls, 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  test(
    'persists concurrent writes across database reopen without Keychain',
    () async {
      await Future.wait([
        storage.write(key: 'llm_api_key', value: 'test-llm'),
        storage.write(key: 'ocr_api_key', value: 'test-ocr'),
        storage.write(key: 'asr_api_key', value: 'test-asr'),
      ]);
      await db.close();
      db = await databaseFactoryFfi.openDatabase(path);
      final reopened = MacosLocalConfigStorage(database: () async => db);
      expect(await reopened.readAll(), {
        'llm_api_key': 'test-llm',
        'ocr_api_key': 'test-ocr',
        'asr_api_key': 'test-asr',
      });
      await reopened.write(key: 'llm_api_key', value: 'replacement');
      expect(await reopened.read(key: 'llm_api_key'), 'replacement');
      await reopened.write(key: 'llm_api_key', value: null);
      expect(await reopened.containsKey(key: 'llm_api_key'), isFalse);
      expect(await reopened.read(key: 'unknown'), isNull);
    },
  );

  test(
    'scoped Hub identity survives and deleteAll preserves unrelated settings',
    () async {
      await db.insert('settings', {
        'key': 'onboarding_completed',
        'value': 'true',
      });
      await storage.write(key: 'api_key', value: 'default');
      const scope = MacOsOptions(accountName: 'peipal.publisher');
      await storage.write(key: 'api_key', value: 'scoped', mOptions: scope);
      expect(await storage.read(key: 'api_key', mOptions: scope), 'scoped');
      final hub = HubService(storage);
      final identity = await hub.ownerKey();
      expect(
        await HubService(
          MacosLocalConfigStorage(database: () async => db),
        ).ownerKey(),
        identity,
      );
      await storage.deleteAll();
      expect(await storage.readAll(), isEmpty);
      expect(await storage.readAll(mOptions: scope), {'api_key': 'scoped'});
      expect(
        (await db.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['onboarding_completed'],
        )).single['value'],
        'true',
      );
    },
  );

  test('macOS application provider selects local storage', () {
    if (!Platform.isMacOS) return;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(secureStorageProvider),
      isA<MacosLocalConfigStorage>(),
    );
  });

  test('provider startup ignores old single-provider keys and writes no mirrors', () async {
    for (final kind in ['llm', 'asr', 'ocr']) {
      await storage.write(key: '${kind}_api_key', value: 'unused-old-key');
      await storage.write(key: '${kind}_base_url', value: 'https://old.invalid');
    }
    final container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);
    final ready = List.generate(3, (_) => Completer<void>());
    container.listen(llmProvidersProvider, (_, state) {
      if (!state.isLoading && !ready[0].isCompleted) ready[0].complete();
    }, fireImmediately: true);
    container.listen(asrProvidersProvider, (_, state) {
      if (!state.isLoading && !ready[1].isCompleted) ready[1].complete();
    }, fireImmediately: true);
    container.listen(ocrProvidersProvider, (_, state) {
      if (!state.isLoading && !ready[2].isCompleted) ready[2].complete();
    }, fireImmediately: true);
    await Future.wait(ready.map((c) => c.future)).timeout(const Duration(seconds: 5));
    expect(container.read(llmProvidersProvider).providers.every((p) => p.apiKey.isEmpty), isTrue);
    expect(container.read(asrProvidersProvider).providers.every((p) => p.apiKey.isEmpty), isTrue);
    expect(container.read(ocrProvidersProvider).providers.every((p) => p.apiKey.isEmpty), isTrue);
    await container.read(llmProvidersProvider.notifier).setActiveProvider('deepseek');
    final values = await storage.readAll();
    expect(values['llm_api_key'], 'unused-old-key');
    expect(values.containsKey('llm_model'), isFalse);
    expect(values.containsKey('llm_providers_matrix_v1'), isTrue);
  });

  test(
    'current backup format restores API and document settings to SQLite',
    () async {
      BackupService service() => BackupService(
        templateRepo: InMemoryTemplateRepo(),
        contentTemplateRepo: InMemoryContentTemplateRepo(),
        favoriteDiagnosisRepo: InMemoryFavDiagRepo(),
        settingsRepo: InMemorySettingsRepo(),
        secureStorage: storage,
      );
      await storage.write(key: 'llm_providers_matrix_v1', value: jsonEncode([
        {'id': 'deepseek', 'apiKey': 'test-backup-key'},
      ]));
      await DocumentParserConfigStore(storage).importSettings({
        'activeProviderId': 'deepseek',
        'providers': [
          {'id': 'deepseek', 'apiKey': 'test-document-key'},
        ],
      });
      final hub = HubService(storage);
      final owner = await hub.ownerKey();
      await hub.setAdminToken('test-admin-token');
      final bundle = await service().exportBundle(const BackupExportOptions());
      expect(jsonEncode(bundle), contains('test-backup-key'));
      expect(jsonEncode(bundle), isNot(contains(owner)));
      expect(jsonEncode(bundle), isNot(contains('test-admin-token')));
      final withoutApis = await service().exportBundle(
        const BackupExportOptions(apiConfigs: false),
      );
      expect(jsonEncode(withoutApis), isNot(contains('test-backup-key')));
      await storage.deleteAll();
      final result = await service().importBundle(bundle);
      expect(result.isSuccess, isTrue);
      final restored = jsonDecode((await storage.read(key: 'llm_providers_matrix_v1'))!) as List;
      expect(restored.single['apiKey'], 'test-backup-key');
      expect(
        (await DocumentParserConfigStore(
          storage,
        ).load()).activeProvider!.apiKey,
        'test-document-key',
      );
    },
  );

  test(
    'macOS restricts database directory, database and existing sidecars',
    () async {
      if (!Platform.isMacOS) return;
      for (final suffix in ['-wal', '-shm', '-journal']) {
        await File('$path$suffix').create();
      }
      await restrictMacosDatabaseFiles(path);
      final result = await Process.run('/usr/bin/stat', [
        '-f',
        '%Lp',
        directory.path,
        path,
        '$path-wal',
        '$path-shm',
        '$path-journal',
      ]);
      expect(result.exitCode, 0);
      expect((result.stdout as String).trim().split('\n'), [
        '700',
        '600',
        '600',
        '600',
        '600',
      ]);
    },
  );
}
