import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:peipal/data/repositories/catalog_repository.dart';
import 'package:peipal/data/repositories/catalog_tags_repository.dart';
import 'package:peipal/data/repositories/content_template_repository.dart';
import 'package:peipal/data/repositories/favorite_diagnosis_repository.dart';
import 'package:peipal/data/repositories/settings_repository.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/data/services/engine_c/engine_c_models.dart';
import 'package:peipal/data/services/engine_c/template_bundle_engine.dart';
import 'package:peipal/data/services/hub/hub_service.dart';
import 'package:peipal/domain/models/catalog_definition.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/favorite_diagnosis.dart';
import 'package:peipal/domain/models/pipeline_graph.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/domain/models/typing_action_block.dart';
import 'package:peipal/domain/models/typing_profile.dart';

class _MemTemplateRepo implements TemplateRepository {
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

class _MemContentTemplateRepo implements ContentTemplateRepository {
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
  Future<void> deleteByStructure(String sid) async =>
      _map.removeWhere((k, v) => v.structureTemplateId == sid);
}

class _MemFavDiagRepo implements FavoriteDiagnosisRepository {
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
  }) async =>
      _map.values
          .where((d) =>
              d.code == code && d.name == name && d.catalogType == catalogType)
          .firstOrNull;

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
  }) async =>
      _map.removeWhere((k, v) =>
          v.code == code && v.name == name && v.catalogType == catalogType);

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
}

class _MemSettingsRepo implements SettingsRepository {
  final Map<String, String> _map = {};

  @override
  Future<String?> get(String key) async => _map[key];

  @override
  Future<void> set(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);
}

class _FakeSecureStorage extends Fake implements FlutterSecureStorage {
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


class _MemCatalogRepo implements CatalogRepository {
  final Map<String, CatalogDefinition> _map = {};

  @override
  Future<List<CatalogDefinition>> getAll({bool includeDisabled = true}) async =>
      _map.values.toList();

  @override
  Future<CatalogDefinition?> getById(String id) async => _map[id];

  @override
  Future<void> insert(CatalogDefinition catalog) async =>
      _map[catalog.id] = catalog;

  @override
  Future<void> update(CatalogDefinition catalog) async =>
      _map[catalog.id] = catalog;

  @override
  Future<void> delete(String id) async => _map.remove(id);
}

class _MemCatalogTagsRepo implements CatalogTagsRepository {
  final Map<String, Set<String>> _map = {};

  @override
  Future<List<String>> getAll(String catalogType) async =>
      (_map[catalogType] ?? <String>{}).toList();

  @override
  Future<void> addTag(String catalogType, String tag) async =>
      _map.putIfAbsent(catalogType, () => <String>{}).add(tag);

  @override
  Future<void> renameTag(
      String catalogType, String oldTag, String newTag) async {
    final tags = _map[catalogType];
    if (tags != null && tags.remove(oldTag)) tags.add(newTag);
  }

  @override
  Future<void> deleteTag(String catalogType, String tag) async =>
      _map[catalogType]?.remove(tag);

  @override
  Future<void> deleteByCatalog(String catalogType) async =>
      _map.remove(catalogType);
}

void main() {
  late _MemTemplateRepo tRepo;
  late _MemContentTemplateRepo ctRepo;
  late _MemFavDiagRepo dRepo;
  late _MemSettingsRepo sRepo;
  late _FakeSecureStorage sec;
  late TemplateBundleEngine engine;

  setUp(() {
    tRepo = _MemTemplateRepo();
    ctRepo = _MemContentTemplateRepo();
    dRepo = _MemFavDiagRepo();
    sRepo = _MemSettingsRepo();
    sec = _FakeSecureStorage();
    engine = TemplateBundleEngine(
      templateRepo: tRepo,
      contentTemplateRepo: ctRepo,
      favoriteDiagnosisRepo: dRepo,
      catalogRepo: _MemCatalogRepo(),
      catalogTagsRepo: _MemCatalogTagsRepo(),
      settingsRepo: sRepo,
      secureStorage: sec,
    );
  });

  test(
      'Engine C: exporting a content template inlines linked catalog entries',
      () async {
    final struct = Template(
      id: 'st_cardio',
      name: '心内入院记录',
      slots: const [
        TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
        TemplateSlot(
          key: 'diag',
          label: '诊断',
          type: SlotType.text,
          catalogType: 'diagnosis',
        ),
      ],
    );
    await tRepo.insert(struct);

    final ct = ContentTemplate(
      id: 'ct_hf',
      structureTemplateId: 'st_cardio',
      name: '心衰示范',
      globalGuidance: '突出呼吸困难诱因',
      slots: const {
        'diag': SlotContent(
          guidance: '优先写心功能分级',
          catalogTags: ['心衰专病'],
        ),
      },
    );
    await ctRepo.insert(ct);

    await dRepo.insert(FavoriteDiagnosis(
      id: 'd1',
      code: 'I50.900',
      name: '心力衰竭',
      tags: const ['心衰专病'],
    ));
    await dRepo.insert(FavoriteDiagnosis(
      id: 'd2',
      code: 'J00',
      name: '急性鼻咽炎',
      tags: const ['呼吸科'],
    ));

    // Export only this content template (with host structure + linked diagnoses)
    final jsonStr = await engine.exportJsonString(EngineCExportRequest(
      families: const [
        StructureFamilyExportSelection(
          templateId: 'st_cardio',
          includePipeline: false,
          selectedTypingProfileIds: {},
          selectedContentTemplateIds: {'ct_hf'},
          includeLinkedDiagnoses: true,
        ),
      ],
    ));

    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final units = map['structure_units'] as List;
    expect(units, hasLength(1));
    expect(units.first['structure']['name'], '心内入院记录');
    expect(units.first['content_templates'], hasLength(1));

    // Linked entries are no longer exported as a separate library; they are
    // inlined into the content template guidance.
    expect(map.containsKey('favorite_diagnoses'), isFalse);
    expect(map.containsKey('catalog_entries'), isFalse);

    final ctMap = (units.first['content_templates'] as List).first
        as Map<String, dynamic>;
    final slotData =
        Map<String, dynamic>.from(ctMap['slots'] as Map<String, dynamic>);
    final diagSlot = Map<String, dynamic>.from(slotData['diag'] as Map);
    final guidance = diagSlot['guidance'] as String;
    expect(guidance, contains('标准诊断词条[心衰专病]：心力衰竭 (I50.900)'));
    expect(guidance, isNot(contains('[CATALOG:')));
    expect(diagSlot.containsKey('catalog_refs'), isFalse);
    expect(diagSlot.containsKey('catalog_tags'), isFalse);

    // Full backup also carries the catalog library, so @mentions stay live.
    final fullJson = await engine.exportJsonString(EngineCExportRequest(
      families: const [
        StructureFamilyExportSelection(
          templateId: 'st_cardio',
          includePipeline: false,
          selectedTypingProfileIds: {},
          selectedContentTemplateIds: {'ct_hf'},
        ),
      ],
      includeAllDiagnoses: true,
    ));
    final fullMap = jsonDecode(fullJson) as Map<String, dynamic>;
    final fullCt = ((fullMap['structure_units'] as List).first
        ['content_templates'] as List).first as Map<String, dynamic>;
    final fullSlot =
        Map<String, dynamic>.from((fullCt['slots'] as Map)['diag'] as Map);
    expect(fullSlot['guidance'] as String, contains('[CATALOG:diagnosis:心衰专病]'));
    expect(fullSlot.containsKey('catalog_refs'), isTrue);
    expect(fullMap['catalog_entries'], isNotNull);
  });

  test(
      'Engine C Level-1 Match & Level-2 Fork: when structure slots match, reuse local structure and fork conflicting typing profile & content template',
      () async {
    // Seed local DB with structure "住院病历"
    final baseSlots = const [
      TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
      TemplateSlot(key: 'pi', label: '现病史', type: SlotType.multiline),
    ];

    final localTemplate = Template(
      id: 'local_struct_1',
      name: '住院病历',
      slots: baseSlots,
      typingProfiles: [
        TypingProfile(
          id: 'p_local',
          name: '卫宁HIS',
          blocks: [
            FieldInputBlock(fieldKey: 'cc', postKeys: const ['{TAB}']),
          ],
        ),
      ],
    );
    await tRepo.insert(localTemplate);

    await ctRepo.insert(ContentTemplate(
      id: 'ct_local',
      structureTemplateId: 'local_struct_1',
      name: '冠心病模板',
      globalGuidance: '本地旧版规范',
    ));

    // Construct an incoming bundle with SAME structure slots,
    // but modified "卫宁HIS" typing profile (uses {ENTER} instead of {TAB})
    // and modified "冠心病模板" content template + 1 brand new content template
    final incomingUnit = StructureGroundedUnit(
      structure: Template(
        id: 'remote_struct_999',
        name: '住院病历',
        slots: baseSlots,
      ),
      hasPipeline: false,
      typingProfiles: [
        TypingProfile(
          id: 'p_remote',
          name: '卫宁HIS',
          blocks: [
            FieldInputBlock(fieldKey: 'cc', postKeys: const ['{ENTER}']),
          ],
        ),
      ],
      contentTemplates: [
        ContentTemplate(
          id: 'ct_remote_1',
          structureTemplateId: 'remote_struct_999',
          name: '冠心病模板',
          globalGuidance: '云端新版更详细的四段式规范',
        ),
        ContentTemplate(
          id: 'ct_remote_2',
          structureTemplateId: 'remote_struct_999',
          name: '高血压模板',
          globalGuidance: '血压分级规范',
        ),
      ],
    );

    final envelope = EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      units: [incomingUnit],
    );

    final plan = await engine.analyzeImport(envelope.toJson());
    expect(plan.unitPlans, hasLength(1));

    final uPlan = plan.unitPlans.first;
    // Level 1: Slots match -> reuse local structure!
    expect(uPlan.slotsSignatureMatched, isTrue);
    expect(uPlan.structureAction, StructureMatchAction.matchAndReuseLocal);

    // Level 2B: "卫宁HIS" profile differs -> forkChildCopy!
    expect(uPlan.typingProfilePlans.first.action,
        ChildItemMatchAction.forkChildCopy);

    // Level 2C: "冠心病模板" differs -> forkChildCopy; "高血压模板" is new -> createNew!
    expect(uPlan.contentTemplatePlans[0].action,
        ChildItemMatchAction.forkChildCopy);
    expect(
        uPlan.contentTemplatePlans[1].action, ChildItemMatchAction.createNew);

    // Execute plan
    final res = await engine.executeImportPlan(plan);
    expect(res.reusedStructures, 1);
    expect(res.forkedStructures, 0);
    expect(res.forkedTypingProfiles, 1);
    expect(res.forkedContentTemplates, 1);
    expect(res.addedContentTemplates, 1);

    // Verify local structure was NOT duplicated, and now has both "卫宁HIS" and "卫宁HIS (副本)"
    final allStructs = await tRepo.getAll();
    expect(allStructs, hasLength(1));
    expect(allStructs.first.id, 'local_struct_1');
    expect(
      allStructs.first.typingProfiles.map((p) => p.name).toList(),
      containsAll(['卫宁HIS', '卫宁HIS (副本)']),
    );

    // Verify content templates under 'local_struct_1'
    final allCts = await ctRepo.getByStructure('local_struct_1');
    expect(
      allCts.map((c) => c.name).toList(),
      containsAll(['冠心病模板', '冠心病模板 (副本)', '高血压模板']),
    );
  });

  test(
      'Engine C Level-1 Fork: when structure has same name but different slots, fork entire structure as copy',
      () async {
    await tRepo.insert(Template(
      id: 'local_1',
      name: '入院记录',
      slots: const [
        TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
      ],
    ));

    // Incoming "入院记录" has an extra slot 'past_history' -> Level 1 mismatch!
    final incomingUnit = StructureGroundedUnit(
      structure: Template(
        id: 'remote_1',
        name: '入院记录',
        slots: const [
          TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
          TemplateSlot(key: 'past_history', label: '既往史', type: SlotType.text),
        ],
        pipeline: PipelineGraph(
          nodes: [PipelineNode(label: '阶段1', slotKeys: const ['cc'])],
        ),
      ),
      hasPipeline: true,
      contentTemplates: [
        ContentTemplate(
          structureTemplateId: 'remote_1',
          name: '标准示范',
          globalGuidance: '完整版规范',
        ),
      ],
    );

    final envelope = EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      units: [incomingUnit],
    );

    final plan = await engine.analyzeImport(envelope.toJson());
    final uPlan = plan.unitPlans.first;

    expect(uPlan.slotsSignatureMatched, isFalse);
    expect(uPlan.structureAction, StructureMatchAction.forkAsCopy);
    expect(uPlan.slotDiffSummary, contains('past_history'));

    final res = await engine.executeImportPlan(plan);
    expect(res.forkedStructures, 1);

    final allStructs = await tRepo.getAll();
    expect(allStructs, hasLength(2));
    final forked = allStructs.firstWhere((t) => t.name == '入院记录 (副本)');
    expect(forked.slots, hasLength(2));

    // Content template should be attached to the newly forked structure ID
    final forkedCts = await ctRepo.getByStructure(forked.id);
    expect(forkedCts, hasLength(1));
    expect(forkedCts.first.name, '标准示范');
  });

  test(
      'Engine C Diagnosis standalone import deduplicates by code+name and merges tags',
      () async {
    await dRepo.insert(FavoriteDiagnosis(
      id: 'd_existing',
      code: 'I10.x00',
      name: '原发性高血压',
      tags: const ['心内科'],
    ));

    final envelope = EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      diagnoses: [
        FavoriteDiagnosis(
          code: 'I10.x00',
          name: '原发性高血压',
          tags: const ['门诊高频', '慢病'],
          note: '注意危险分层',
        ),
        FavoriteDiagnosis(
          code: 'E11.900',
          name: '2型糖尿病',
          tags: const ['内分泌'],
        ),
      ],
      diagnosisTags: const ['门诊高频', '慢病', '内分泌'],
    );

    final plan = await engine.analyzeImport(envelope.toJson());
    expect(plan.diagnosisPlan.newDiagnoses, hasLength(1));
    expect(plan.diagnosisPlan.mergedTagDiagnoses, hasLength(1));

    final res = await engine.executeImportPlan(plan);
    expect(res.addedDiagnoses, 1);
    expect(res.mergedDiagnoses, 1);

    final updated = await dRepo.findByCodeAndName('I10.x00', '原发性高血压');
    expect(updated?.tags, containsAll(['心内科', '门诊高频', '慢病']));
    expect(updated?.note, '注意危险分层');
  });

  test(
      'Engine C matches the same id before name, and does not claim one local template twice',
      () async {
    const slots = [
      TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
    ];
    await tRepo.insert(Template(
      id: 'abc',
      name: '入院记录',
      slots: slots,
    ));
    await tRepo.insert(Template(
      id: 'def',
      name: '心内入院',
      slots: slots,
    ));

    final renamed = StructureGroundedUnit(
      structure: Template(id: 'abc', name: '心内入院', slots: slots),
      hasPipeline: false,
    );
    final sameNameAsSecond = StructureGroundedUnit(
      structure: Template(id: 'remote', name: '心内入院', slots: slots),
      hasPipeline: false,
    );

    final plan = await engine.analyzeImport(EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      units: [renamed, sameNameAsSecond],
    ).toJson());

    expect(plan.unitPlans[0].matchedLocalStructure?.id, 'abc');
    expect(plan.unitPlans[0].structureAction,
        StructureMatchAction.matchAndReuseLocal);
    expect(plan.unitPlans[1].matchedLocalStructure?.id, 'def');
  });

  test('Engine C treats typing-profile key overrides as a real difference',
      () async {
    const slots = [
      TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
    ];
    await tRepo.insert(Template(
      id: 'local_1',
      name: '入院记录',
      slots: slots,
      typingProfiles: [
        TypingProfile(
          name: '卫宁HIS',
          overrides: const {
            'cc': SlotKeyOverride(post: ['{TAB}']),
          },
        ),
      ],
    ));

    final plan = await engine.analyzeImport(EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      units: [
        StructureGroundedUnit(
          structure: Template(id: 'remote', name: '入院记录', slots: slots),
          hasPipeline: false,
          typingProfiles: [
            TypingProfile(
              name: '卫宁HIS',
              overrides: const {
                'cc': SlotKeyOverride(post: ['{ENTER}']),
              },
            ),
          ],
        ),
      ],
    ).toJson());

    expect(plan.unitPlans.first.typingProfilePlans.first.action,
        ChildItemMatchAction.forkChildCopy);
  });

  test('Engine C overwrite updates the existing content template in place',
      () async {
    const slots = [
      TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
    ];
    await tRepo.insert(Template(id: 'local_1', name: '入院记录', slots: slots));
    await ctRepo.insert(ContentTemplate(
      id: 'ct_local',
      structureTemplateId: 'local_1',
      name: '标准示范',
      globalGuidance: '旧规范',
    ));

    final plan = await engine.analyzeImport(EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      units: [
        StructureGroundedUnit(
          structure: Template(id: 'remote', name: '入院记录', slots: slots),
          hasPipeline: false,
          contentTemplates: [
            ContentTemplate(
              structureTemplateId: 'remote',
              name: '标准示范',
              globalGuidance: '新规范',
            ),
          ],
        ),
      ],
    ).toJson());
    plan.unitPlans.first.contentTemplatePlans.first.action =
        ChildItemMatchAction.overwriteLocalChild;

    await engine.executeImportPlan(plan);

    final cts = await ctRepo.getByStructure('local_1');
    expect(cts, hasLength(1));
    expect(cts.single.id, 'ct_local');
    expect(cts.single.globalGuidance, '新规范');
  });

  test('Engine C: exports and imports both diagnoses and procedures with tags',
      () async {
    await dRepo.insert(FavoriteDiagnosis(
      id: 'diag_1',
      catalogType: 'diagnosis',
      code: 'I10.01',
      name: '原发性高血压',
      tags: ['心内科', '慢性病'],
    ));
    await dRepo.insert(FavoriteDiagnosis(
      id: 'proc_1',
      catalogType: 'procedure',
      code: '36.06',
      name: '经皮冠状动脉药物支架置入术',
      tags: ['心内介入', '四级手术'],
    ));
    await sRepo.set('diagnosis_tags', jsonEncode(['心内科', '慢性病']));
    await sRepo.set('procedure_tags', jsonEncode(['心内介入', '四级手术']));

    final exportedJson = await engine.exportJsonString(
      const EngineCExportRequest(includeAllDiagnoses: true),
    );
    final map = jsonDecode(exportedJson) as Map<String, dynamic>;
    expect(map['favorite_diagnoses'], hasLength(2));
    expect(map['diagnosis_tags'], contains('心内科'));
    expect(map['procedure_tags'], contains('心内介入'));

    // 导入到全新干净存储
    final dRepo2 = _MemFavDiagRepo();
    final sRepo2 = _MemSettingsRepo();
    final cTags2 = _MemCatalogTagsRepo();
    final engine2 = TemplateBundleEngine(
      templateRepo: _MemTemplateRepo(),
      contentTemplateRepo: _MemContentTemplateRepo(),
      favoriteDiagnosisRepo: dRepo2,
      catalogRepo: _MemCatalogRepo(),
      catalogTagsRepo: cTags2,
      settingsRepo: sRepo2,
      secureStorage: _FakeSecureStorage(),
    );

    final plan = await engine2.analyzeImport(map);
    expect(plan.diagnosisPlan.newDiagnosisCount, 1);
    expect(plan.diagnosisPlan.newProcedureCount, 1);
    expect(plan.diagnosisPlan.newTags, contains('心内科'));
    expect(plan.diagnosisPlan.newProcedureTags, contains('心内介入'));

    final result = await engine2.executeImportPlan(plan);
    expect(result.addedDiagnoses, 1);
    expect(result.addedProcedures, 1);

    final allImported = await dRepo2.getAll();
    expect(allImported, hasLength(2));
    expect(allImported.any((d) => d.catalogType == 'diagnosis' && d.name == '原发性高血压'), isTrue);
    expect(allImported.any((d) => d.catalogType == 'procedure' && d.name == '经皮冠状动脉药物支架置入术'), isTrue);

    expect(await cTags2.getAll('diagnosis'), contains('心内科'));
    expect(await cTags2.getAll('procedure'), contains('心内介入'));
  });

  test('Engine C: exports and imports a custom catalog library', () async {
    final cRepo = _MemCatalogRepo();
    final tagsRepo = _MemCatalogTagsRepo();
    final entriesRepo = _MemFavDiagRepo();
    final now = DateTime.now();
    await cRepo.insert(CatalogDefinition(
      id: 'tcm',
      name: '中医库',
      sourceKind: CatalogSourceKind.managed,
      sortOrder: 10,
      createdAt: now,
      updatedAt: now,
    ));
    await entriesRepo.insert(FavoriteDiagnosis(
      catalogType: 'tcm',
      code: 'TCM-1',
      name: '桂枝汤',
      tags: const ['方剂'],
    ));
    await tagsRepo.addTag('tcm', '方剂');

    final exporter = TemplateBundleEngine(
      templateRepo: _MemTemplateRepo(),
      contentTemplateRepo: _MemContentTemplateRepo(),
      favoriteDiagnosisRepo: entriesRepo,
      catalogRepo: cRepo,
      catalogTagsRepo: tagsRepo,
      settingsRepo: _MemSettingsRepo(),
      secureStorage: _FakeSecureStorage(),
    );

    final jsonStr = await exporter.exportJsonString(
      const EngineCExportRequest(
        includeAllDiagnoses: true,
        catalogTypes: {'tcm'},
      ),
    );
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    expect(map['catalogs'], hasLength(1));
    expect((map['catalogs'] as List).first['name'], '中医库');
    expect((map['catalog_tags'] as Map)['tcm'], contains('方剂'));
    final exportedEntries = map['catalog_entries'] as List;
    expect(exportedEntries, hasLength(1));
    expect(exportedEntries.first['catalog_type'], 'tcm');

    final cRepo2 = _MemCatalogRepo();
    final tagsRepo2 = _MemCatalogTagsRepo();
    final entriesRepo2 = _MemFavDiagRepo();
    final importer = TemplateBundleEngine(
      templateRepo: _MemTemplateRepo(),
      contentTemplateRepo: _MemContentTemplateRepo(),
      favoriteDiagnosisRepo: entriesRepo2,
      catalogRepo: cRepo2,
      catalogTagsRepo: tagsRepo2,
      settingsRepo: _MemSettingsRepo(),
      secureStorage: _FakeSecureStorage(),
    );

    final plan = await importer.analyzeImport(map);
    expect(plan.diagnosisPlan.newDiagnoses, hasLength(1));
    await importer.executeImportPlan(plan);

    final restoredCatalogs = await cRepo2.getAll();
    expect(
      restoredCatalogs.any((c) => c.id == 'tcm' && c.name == '中医库'),
      isTrue,
    );
    final restoredEntries = await entriesRepo2.getAll();
    expect(restoredEntries.single.catalogType, 'tcm');
    expect(restoredEntries.single.name, '桂枝汤');
    expect(await tagsRepo2.getAll('tcm'), contains('方剂'));
  });

  test('Engine C shares templates while leaving publishing identity local', () async {
    await tRepo.insert(Template(id: 'shared-structure', name: '检查记录', slots: const [
      TemplateSlot(key: 'result', label: '检查结果', type: SlotType.text),
    ]));
    await ctRepo.insert(ContentTemplate(id: 'shared-content',
      structureTemplateId: 'shared-structure', name: '通用检查', globalGuidance: '按实际情况填写'));
    await sec.write(key: 'hub_owner_key', value: 'old-device-a-owner');
    final hubA = HubService(sec);
    final ownerA = await hubA.ownerKey();
    final bundle = jsonDecode(await engine.exportJsonString(const EngineCExportRequest(
      families: [StructureFamilyExportSelection(templateId: 'shared-structure')],
      includeApiConfigs: true,
    ))) as Map<String, dynamic>;
    final exportedText = jsonEncode(bundle);
    expect(exportedText, isNot(contains(ownerA)));
    expect(exportedText, isNot(contains('old-device-a-owner')));
    expect((bundle['api_configs'] as Map).containsKey('hub_owner_key'), isFalse);
    bundle['api_configs'] = <String, dynamic>{
      ...Map<String, dynamic>.from(bundle['api_configs'] as Map),
      'hub_owner_key': 'old-device-a-owner',
      'hub_publisher_key_v2_injected': ownerA,
    };
    final storageB = _FakeSecureStorage();
    final hubB = HubService(storageB);
    final ownerB = await hubB.ownerKey();
    final templatesB = _MemTemplateRepo();
    final contentsB = _MemContentTemplateRepo();
    final importer = TemplateBundleEngine(
      templateRepo: templatesB, contentTemplateRepo: contentsB,
      favoriteDiagnosisRepo: _MemFavDiagRepo(), catalogRepo: _MemCatalogRepo(),
      catalogTagsRepo: _MemCatalogTagsRepo(), settingsRepo: _MemSettingsRepo(),
      secureStorage: storageB,
    );
    final result = await importer.executeImportPlan(await importer.analyzeImport(bundle));
    expect(result.isSuccess, isTrue);
    expect((await templatesB.getAll()).single.id, 'shared-structure');
    expect((await contentsB.getAll()).single.name, '通用检查');
    expect(await hubB.ownerKey(), ownerB);
    expect(ownerB, isNot(ownerA));
    expect(await storageB.read(key: 'hub_owner_key'), isNull);
    expect(await storageB.read(key: 'hub_publisher_key_v2_injected'), isNull);
  });

  test('Engine C: exports and imports AI provider matrix with native list & smart merge',
      () async {
    final llmMatrix = [
      {
        'id': 'deepseek',
        'name': 'DeepSeek',
        'apiKey': 'sk-deepseek-test',
        'baseUrl': 'https://api.deepseek.com/v1',
        'selectedModel': 'deepseek-v4-pro',
        'reasoningEfforts': {'deepseek-v4-pro': 'max', 'deepseek-flash': ''},
      },
    ];
    final asrMatrix = [
      {
        'id': 'zhipu',
        'name': '智谱 ASR',
        'apiKey': 'zhipu-asr-key',
        'baseUrl': 'https://open.bigmodel.cn/api/paas/v4',
        'selectedModel': 'glm-asr-2512',
      },
    ];
    final ocrMatrix = [
      {
        'id': 'modelbest',
        'name': '面壁智能',
        'apiKey': 'modelbest-key',
        'baseUrl': 'https://api.modelbest.cn/v1',
        'selectedModel': 'document-parse',
      },
    ];

    await sec.write(key: 'llm_providers_matrix_v1', value: jsonEncode(llmMatrix));
    await sec.write(key: 'llm_active_provider_id_v1', value: 'deepseek');
    await sec.write(key: 'asr_providers_matrix_v1', value: jsonEncode(asrMatrix));
    await sec.write(key: 'asr_active_provider_id_v1', value: 'zhipu');
    await sec.write(key: 'ocr_providers_matrix_v1', value: jsonEncode(ocrMatrix));
    await sec.write(key: 'ocr_active_provider_id_v1', value: 'modelbest');
    await sRepo.set('ocr_concurrency', '4');

    final exportedJson = await engine.exportJsonString(
      const EngineCExportRequest(includeApiConfigs: true),
    );
    final map = jsonDecode(exportedJson) as Map<String, dynamic>;
    final apis = map['api_configs'] as Map<String, dynamic>;
    expect(apis['llm']['providers'], isList);
    expect((apis['llm']['providers'] as List).first['id'], 'deepseek');
    expect((apis['llm']['providers'] as List).first['reasoningEfforts'],
        {'deepseek-v4-pro': 'max', 'deepseek-flash': ''});
    expect(apis['ocr']['ocr_concurrency'], '4');

    // 导入到本地已有其他供应商 (如 kimi) 的设备中，测试智能合并
    final sec2 = _FakeSecureStorage();
    final sRepo2 = _MemSettingsRepo();
    final localKimi = [
      {
        'id': 'deepseek',
        'reasoningEfforts': {
          'deepseek-v4-pro': 'low',
          'deepseek-flash': 'high',
          'another-model': 'high',
        },
      },
      {
        'id': 'moonshot',
        'name': 'Kimi',
        'apiKey': 'sk-kimi-local',
        'baseUrl': 'https://api.moonshot.cn/v1',
        'selectedModel': 'moonshot-v1-8k',
      },
    ];
    await sec2.write(key: 'llm_providers_matrix_v1', value: jsonEncode(localKimi));

    final engine2 = TemplateBundleEngine(
      templateRepo: _MemTemplateRepo(),
      contentTemplateRepo: _MemContentTemplateRepo(),
      favoriteDiagnosisRepo: _MemFavDiagRepo(),
      catalogRepo: _MemCatalogRepo(),
      catalogTagsRepo: _MemCatalogTagsRepo(),
      settingsRepo: sRepo2,
      secureStorage: sec2,
    );

    final plan = await engine2.analyzeImport(map);
    expect(plan.apiConfigsSummary, isNotNull);
    final result = await engine2.executeImportPlan(plan);
    expect(result.importedApiConfigs, isTrue);

    final mergedRaw = await sec2.read(key: 'llm_providers_matrix_v1');
    final mergedList = jsonDecode(mergedRaw!) as List;
    expect(mergedList.any((p) => p['id'] == 'moonshot' && p['apiKey'] == 'sk-kimi-local'), isTrue);
    expect(mergedList.any((p) => p['id'] == 'deepseek' && p['apiKey'] == 'sk-deepseek-test'), isTrue);
    expect(await sec2.read(key: 'llm_active_provider_id_v1'), 'deepseek');
    expect(mergedList.firstWhere((p) => p['id'] == 'deepseek')['reasoningEfforts'], {
      'deepseek-v4-pro': 'max',
      'deepseek-flash': '',
      'another-model': 'high',
    });
    expect(await sec2.read(key: 'llm_reasoning_effort'), 'max');

    // Older exports omit effort; they must retain the locally configured levels.
    final legacyProvider = Map<String, dynamic>.from(llmMatrix.first)
      ..remove('reasoningEfforts');
    final legacyPlan = await engine2.analyzeImport({
      ...map,
      'api_configs': {
        'llm': {'providers': [legacyProvider], 'activeProviderId': 'deepseek'},
      },
    });
    await engine2.executeImportPlan(legacyPlan);
    expect(await sec2.read(key: 'llm_reasoning_effort'), 'max');

    final importedConcurrency = await sRepo2.get('ocr_concurrency');
    expect(importedConcurrency, '4');
  });

  test('DeepSeek OCR and ASR protocols survive export and merge import', () async {
    for (final kind in ['asr', 'ocr']) {
      await sec.write(key: '${kind}_providers_matrix_v1', value: jsonEncode([
        {
          'id': 'deepseek',
          'name': 'DeepSeek',
          'protocol': 'deepseek',
          'baseUrl': 'https://api.deepseek.com/v1',
          'apiKey': 'test-$kind-key',
          'selectedModel': '',
        },
      ]));
      await sec.write(key: '${kind}_active_provider_id_v1', value: 'deepseek');
    }
    final exported = await engine.exportJsonString(
      const EngineCExportRequest(includeApiConfigs: true));
    for (final kind in ['asr', 'ocr']) {
      await sec.write(key: '${kind}_providers_matrix_v1', value: jsonEncode([
        {'id': 'deepseek', 'protocol': 'openaiVision', 'selectedModel': 'old-model'},
      ]));
    }
    final plan = await engine.analyzeImport(jsonDecode(exported) as Map<String, dynamic>);
    await engine.executeImportPlan(plan);
    for (final kind in ['asr', 'ocr']) {
      final raw = await sec.read(key: '${kind}_providers_matrix_v1');
      final restored = (jsonDecode(raw!) as List).firstWhere((p) => p['id'] == 'deepseek');
      expect(restored['protocol'], 'deepseek');
      expect(restored['selectedModel'], '');
      expect(restored['apiKey'], 'test-$kind-key');
      expect(await sec.read(key: '${kind}_provider'), 'deepseek');
    }
  });

  test('Engine C: exports and imports device and UI settings seamlessly',
      () async {
    await sRepo.set('timing_app_defaults', '{"stepDelayMs": 80}');
    await sRepo.set('char_replacement_rules', '{"·": "."}');
    await sRepo.set('floating_overlay_enabled', 'false');
    await sRepo.set('app_font_scale', '1.15');

    final exportedJson = await engine.exportJsonString(
      const EngineCExportRequest(includeDeviceAndOutputConfigs: true),
    );
    final map = jsonDecode(exportedJson) as Map<String, dynamic>;
    final devs = map['device_and_output_configs'] as Map<String, dynamic>;
    expect(devs['char_replacement_rules'], '{"·": "."}');
    expect(devs['app_font_scale'], '1.15');

    final sRepo2 = _MemSettingsRepo();
    final engine2 = TemplateBundleEngine(
      templateRepo: _MemTemplateRepo(),
      contentTemplateRepo: _MemContentTemplateRepo(),
      favoriteDiagnosisRepo: _MemFavDiagRepo(),
      catalogRepo: _MemCatalogRepo(),
      catalogTagsRepo: _MemCatalogTagsRepo(),
      settingsRepo: sRepo2,
      secureStorage: _FakeSecureStorage(),
    );

    final plan = await engine2.analyzeImport(map);
    await engine2.executeImportPlan(plan);

    expect(await sRepo2.get('char_replacement_rules'), '{"·": "."}');
    expect(await sRepo2.get('floating_overlay_enabled'), 'false');
    expect(await sRepo2.get('app_font_scale'), '1.15');
  });
}
