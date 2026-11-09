import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:peipal/data/repositories/content_template_repository.dart';
import 'package:peipal/data/repositories/favorite_diagnosis_repository.dart';
import 'package:peipal/data/repositories/settings_repository.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/data/services/backup/backup_service.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/favorite_diagnosis.dart';
import 'package:peipal/domain/models/template.dart';

class InMemoryTemplateRepo implements TemplateRepository {
  final Map<String, Template> _map = {};

  @override
  Future<List<Template>> getAll() async => _map.values.toList();

  @override
  Future<Template?> getById(String id) async => _map[id];

  @override
  Future<void> insert(Template t) async => _map[t.id] = t;

  @override
  Future<void> update(Template t) async => _map[t.id] = t;

  @override
  Future<void> delete(String id) async => _map.remove(id);
}

class InMemoryContentTemplateRepo implements ContentTemplateRepository {
  final Map<String, ContentTemplate> _map = {};

  @override
  Future<List<ContentTemplate>> getAll() async => _map.values.toList();

  @override
  Future<ContentTemplate?> getById(String id) async => _map[id];

  @override
  Future<List<ContentTemplate>> getByStructure(String sid) async =>
      _map.values.where((c) => c.structureTemplateId == sid).toList();

  @override
  Future<void> insert(ContentTemplate ct) async => _map[ct.id] = ct;

  @override
  Future<void> update(ContentTemplate ct) async => _map[ct.id] = ct;

  @override
  Future<void> delete(String id) async => _map.remove(id);

  @override
  Future<void> deleteByStructure(String structureTemplateId) async {
    _map.removeWhere((k, v) => v.structureTemplateId == structureTemplateId);
  }
}

class InMemoryFavDiagRepo implements FavoriteDiagnosisRepository {
  final Map<String, FavoriteDiagnosis> _map = {};

  @override
  Future<List<FavoriteDiagnosis>> getAll({String? catalogType}) async =>
      _map.values
          .where((d) => catalogType == null || d.catalogType == catalogType)
          .toList();

  @override
  Future<FavoriteDiagnosis?> getById(String id) async => _map[id];

  @override
  Future<FavoriteDiagnosis?> findByCodeAndName(
    String code,
    String name, {
    String catalogType = 'diagnosis',
  }) async {
    return _map.values
        .where((d) =>
            d.code == code && d.name == name && d.catalogType == catalogType)
        .firstOrNull;
  }

  @override
  Future<void> insert(FavoriteDiagnosis d) async => _map[d.id] = d;

  @override
  Future<void> update(FavoriteDiagnosis d) async => _map[d.id] = d;

  @override
  Future<void> delete(String id) async => _map.remove(id);

  @override
  Future<void> deleteByCodeAndName(
    String code,
    String name, {
    String catalogType = 'diagnosis',
  }) async {
    _map.removeWhere((k, v) =>
        v.code == code && v.name == name && v.catalogType == catalogType);
  }


  @override
  Future<List<FavoriteDiagnosis>> search(String catalogType, String query,
      {int limit = 50}) async =>
      _map.values
          .where((d) =>
              d.catalogType == catalogType &&
              (d.name.contains(query) || d.code.contains(query)))
          .take(limit)
          .toList();

  @override
  Future<List<FavoriteDiagnosis>> getPaged(String catalogType,
          {int offset = 0, int limit = 50}) async =>
      _map.values
          .where((d) => d.catalogType == catalogType)
          .skip(offset)
          .take(limit)
          .toList();

  @override
  Future<int> getTotalCount(String catalogType) async =>
      _map.values.where((d) => d.catalogType == catalogType).length;

  @override
  Future<int> countByTag(String catalogType, String tag) async => _map.values
      .where((d) => d.catalogType == catalogType && d.tags.contains(tag))
      .length;

  @override
  Future<void> deleteByCatalog(String catalogType) async =>
      _map.removeWhere((k, v) => v.catalogType == catalogType);

  Future<void> updateOrder(List<String> orderedIds) async {}

  Future<void> updateTags(String id, List<String> tags) async {
    final d = _map[id];
    if (d != null) _map[id] = d.copyWith(tags: tags);
  }
}

class InMemorySettingsRepo implements SettingsRepository {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> set(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}

class InMemorySecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _map = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _map[key];

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
    if (value != null) {
      _map[key] = value;
    } else {
      _map.remove(key);
    }
  }
}

void main() {
  late InMemoryTemplateRepo tRepo;
  late InMemoryContentTemplateRepo ctRepo;
  late InMemoryFavDiagRepo dRepo;
  late InMemorySettingsRepo sRepo;
  late InMemorySecureStorage sec;
  late BackupService service;

  setUp(() {
    tRepo = InMemoryTemplateRepo();
    ctRepo = InMemoryContentTemplateRepo();
    dRepo = InMemoryFavDiagRepo();
    sRepo = InMemorySettingsRepo();
    sec = InMemorySecureStorage();
    service = BackupService(
      templateRepo: tRepo,
      contentTemplateRepo: ctRepo,
      favoriteDiagnosisRepo: dRepo,
      settingsRepo: sRepo,
      secureStorage: sec,
    );
  });

  test('BackupService exports and imports selected bundle cleanly', () async {
    // 1. Seed data
    await tRepo.insert(Template(
      id: 'tmpl_1',
      name: '门诊病历模板',
      version: '1.0',
      slots: const [
        TemplateSlot(
          key: 'chief_complaint',
          label: '主诉',
          type: SlotType.text,
        ),
      ],
    ));

    await ctRepo.insert(ContentTemplate(
      id: 'ct_1',
      structureTemplateId: 'tmpl_1',
      name: '感冒示范',
      globalGuidance: '严格描述发热天数',
    ));

    await dRepo.insert(FavoriteDiagnosis(
      id: 'diag_1',
      code: 'J00',
      name: '急性鼻咽炎（感冒）',
      tags: const ['呼吸科', '常见病'],
    ));
    await sRepo.set('diagnosis_tags', jsonEncode(['呼吸科', '常见病']));

    await sec.write(key: 'llm_api_key', value: 'sk-test123456');
    await sec.write(key: 'llm_model', value: 'gpt-4o');

    // 2. Export all
    final bundle = await service.exportBundle(const BackupExportOptions());

    expect(bundle['templates'], hasLength(1));
    expect(bundle['content_templates'], hasLength(1));
    expect(bundle['favorite_diagnoses'], hasLength(1));
    expect(bundle['api_configs']['llm']['apiKey'], 'sk-test123456');

    // 3. Clear repositories and re-import
    final tRepo2 = InMemoryTemplateRepo();
    final ctRepo2 = InMemoryContentTemplateRepo();
    final dRepo2 = InMemoryFavDiagRepo();
    final sRepo2 = InMemorySettingsRepo();
    final sec2 = InMemorySecureStorage();
    final service2 = BackupService(
      templateRepo: tRepo2,
      contentTemplateRepo: ctRepo2,
      favoriteDiagnosisRepo: dRepo2,
      settingsRepo: sRepo2,
      secureStorage: sec2,
    );

    final res = await service2.importBundle(bundle);

    expect(res.isSuccess, true);
    expect(res.importedTemplates, 1);
    expect(res.importedContentTemplates, 1);
    expect(res.importedDiagnoses, 1);
    expect(res.importedApiConfigs, true);

    // Verify imported data
    final importedTemplate = await tRepo2.getById('tmpl_1');
    expect(importedTemplate?.name, '门诊病历模板');

    final importedDiag = await dRepo2.getById('diag_1');
    expect(importedDiag?.name, '急性鼻咽炎（感冒）');
    expect(importedDiag?.tags, contains('呼吸科'));

    final importedKey = await sec2.read(key: 'llm_api_key');
    expect(importedKey, 'sk-test123456');
  });

  test('BackupService selective export only packs requested items', () async {
    await tRepo.insert(Template(
      id: 'tmpl_2',
      name: '仅导出此模板',
      version: '1.0',
    ));
    await sec.write(key: 'llm_api_key', value: 'secret-key');

    // Only export templates, exclude API keys and diagnoses
    final bundle = await service.exportBundle(const BackupExportOptions(
      templates: true,
      contentTemplates: false,
      favoriteDiagnoses: false,
      apiConfigs: false,
      promptConfigs: false,
      bleAndQrSettings: false,
    ));

    expect(bundle.containsKey('templates'), true);
    expect(bundle.containsKey('content_templates'), false);
    expect(bundle.containsKey('favorite_diagnoses'), false);
    expect(bundle.containsKey('api_configs'), false);
  });
}
