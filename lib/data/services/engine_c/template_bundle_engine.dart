import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/asr_provider.dart';
import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/catalog_mention.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/favorite_diagnosis.dart';
import '../../../domain/models/llm_provider.dart';
import '../../../domain/models/ocr_provider.dart';
import '../../../domain/models/pipeline_graph.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';
import '../../repositories/catalog_repository.dart';
import '../../repositories/catalog_tags_repository.dart';
import '../../repositories/content_template_repository.dart';
import '../../repositories/favorite_diagnosis_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/template_repository.dart';
import 'engine_c_differ.dart';
import 'engine_c_models.dart';

const _uuid = Uuid();

/// 模板家族与诊断包依赖解析引擎（Engine C - Template Bundle & Dependency Resolution Engine）
///
/// 核心职责：
/// 1. 强根基打包编译（Compile）：除独立诊断外，任何结构、解析流程、键入方案或内容模板导出时，
///    均强制将完整的「宿主结构模板（Structure Template）」作为根基信封打包，彻底消灭无根孤儿数据；
/// 2. 逐层树状比对与分叉预检（Layered Tree Match & Fork Analysis）：
///    - 第 1 层比对结构模板字段签名 (`slots`)：匹配则复用本地结构继续深入第 2 层；不匹配则从第 1 层起新建结构副本；
///    - 第 2 层比对解析流程、键入方案与内容模板：同名且内容一致则幂等跳过；同名但内容不同则直接在对应子层新建副本；
///    - 独立层比对常用诊断库：按 `code + name` 去重并智能合并标签集合 (`tags`)；
/// 3. 兼容全量旧版 JSON 格式（`BackupService v1.0`、`structureOnly`、`structureWithPipeline`、`contentTemplate` 等）。
class TemplateBundleEngine {
  final TemplateRepository templateRepo;
  final ContentTemplateRepository contentTemplateRepo;
  final FavoriteDiagnosisRepository favoriteDiagnosisRepo;
  final CatalogRepository catalogRepo;
  final CatalogTagsRepository catalogTagsRepo;
  final SettingsRepository settingsRepo;
  final FlutterSecureStorage secureStorage;

  TemplateBundleEngine({
    required this.templateRepo,
    required this.contentTemplateRepo,
    required this.favoriteDiagnosisRepo,
    required this.catalogRepo,
    required this.catalogTagsRepo,
    required this.settingsRepo,
    required this.secureStorage,
  });

  // ==========================================================================
  // 1. 导出编译器 (Export Compiler)
  // ==========================================================================

  /// 根据细粒度导出请求构建统一的 [EngineCBundleEnvelope]
  Future<EngineCBundleEnvelope> buildExportEnvelope(
    EngineCExportRequest request,
  ) async {
    final units = <StructureGroundedUnit>[];

    // Catalog data is needed to inline @mentions into exported content templates.
    final allCatalogEntries = await favoriteDiagnosisRepo.getAll();
    final allCatalogDefs = await catalogRepo.getAll();
    final entriesByCatalog = <String, List<FavoriteDiagnosis>>{};
    for (final entry in allCatalogEntries) {
      entriesByCatalog.putIfAbsent(entry.catalogType, () => []).add(entry);
    }
    final catalogNames = {for (final c in allCatalogDefs) c.id: c.name};

    // Whether the request also carries catalog library data. When it does,
    // content templates keep live @mentions; otherwise mentions are inlined.
    final effectiveTags = {...request.selectedDiagnosisTags};
    final exportCatalogData = request.includeAllDiagnoses ||
        effectiveTags.isNotEmpty ||
        request.selectedDiagnosisIds.isNotEmpty;
    final effectiveCatalogTypes = exportCatalogData
        ? (request.catalogTypes.isNotEmpty
            ? request.catalogTypes
            : <String>{
                for (final c in allCatalogDefs) c.id,
                for (final e in allCatalogEntries) e.catalogType,
              })
        : <String>{};

    // 1. 编译每个结构模板家族单元（强制附带完整结构骨架）
    for (final family in request.families) {
      final tmpl = await templateRepo.getById(family.templateId);
      if (tmpl == null) continue;

      // 筛选键入方案
      final List<TypingProfile> profiles;
      if (family.selectedTypingProfileIds == null) {
        profiles = List.from(tmpl.typingProfiles);
      } else if (family.selectedTypingProfileIds!.isEmpty) {
        profiles = const [];
      } else {
        profiles = tmpl.typingProfiles
            .where((p) => family.selectedTypingProfileIds!.contains(p.id))
            .toList();
      }

      // 筛选关联的内容模板
      final allCts = await contentTemplateRepo.getByStructure(tmpl.id);
      final List<ContentTemplate> selectedCts;
      if (family.selectedContentTemplateIds == null) {
        selectedCts = allCts;
      } else if (family.selectedContentTemplateIds!.isEmpty) {
        selectedCts = const [];
      } else {
        selectedCts = allCts
            .where((ct) => family.selectedContentTemplateIds!.contains(ct.id))
            .toList();
      }

      // Inline @catalog mentions so exported content templates are self-contained.
      final inlinedCts = [
        for (final ct in selectedCts)
          _inlineContentTemplate(
            ct,
            tmpl,
            entriesByCatalog,
            catalogNames,
            effectiveCatalogTypes,
          ),
      ];

      units.add(StructureGroundedUnit(
        structure: tmpl,
        hasPipeline: family.includePipeline && tmpl.pipeline.nodes.isNotEmpty,
        typingProfiles: profiles,
        contentTemplates: inlinedCts,
      ));
    }

    // 2. 编译通用词条与标签（仅当显式导出词库数据时才携带）
    final exportedDiags = <FavoriteDiagnosis>[];
    final exportedTagsByCatalog = <String, Set<String>>{};

    if (request.includeAllDiagnoses) {
      for (final type in effectiveCatalogTypes) {
        exportedTagsByCatalog[type] = {
          ...await catalogTagsRepo.getAll(type),
        };
      }
      for (final d in allCatalogEntries) {
        if (!effectiveCatalogTypes.contains(d.catalogType)) continue;
        exportedDiags.add(d);
        exportedTagsByCatalog
            .putIfAbsent(d.catalogType, () => <String>{})
            .addAll(d.tags);
      }
    } else if (effectiveTags.isNotEmpty ||
        request.selectedDiagnosisIds.isNotEmpty) {
      for (final type in effectiveCatalogTypes) {
        exportedTagsByCatalog.putIfAbsent(type, () => <String>{});
        final allTags = await catalogTagsRepo.getAll(type);
        exportedTagsByCatalog[type]!.addAll(effectiveTags.intersection(allTags.toSet()));
      }
      for (final d in allCatalogEntries) {
        if (!effectiveCatalogTypes.contains(d.catalogType)) continue;
        final hitId = request.selectedDiagnosisIds.contains(d.id);
        final hitTag = d.tags.any((t) => effectiveTags.contains(t));
        if (hitId || hitTag) {
          exportedDiags.add(d);
          final matched = d.tags.where((t) => effectiveTags.contains(t));
          exportedTagsByCatalog
              .putIfAbsent(d.catalogType, () => <String>{})
              .addAll(matched);
        }
      }
    }

    final exportedDiagTags = exportedTagsByCatalog['diagnosis'] ?? <String>{};
    final exportedProcTags = exportedTagsByCatalog['procedure'] ?? <String>{};

    // 3. 编译可选的全局系统设置（供导入导出中心全量备份使用）
    Map<String, dynamic>? apiConfigs;
    if (request.includeApiConfigs) {
      final providersMatrix =
          await secureStorage.read(key: 'llm_providers_matrix_v1');
      final activeProviderId =
          await secureStorage.read(key: 'llm_active_provider_id_v1');
      final asrProvidersMatrix =
          await secureStorage.read(key: 'asr_providers_matrix_v1');
      final asrActiveProviderId =
          await secureStorage.read(key: 'asr_active_provider_id_v1');
      final ocrProvidersMatrix =
          await secureStorage.read(key: 'ocr_providers_matrix_v1');
      final ocrActiveProviderId =
          await secureStorage.read(key: 'ocr_active_provider_id_v1');
      final ocrConcurrency = await settingsRepo.get('ocr_concurrency');

      dynamic decodeMatrix(String? raw) {
        if (raw == null || raw.trim().isEmpty) return null;
        try {
          return jsonDecode(raw);
        } catch (_) {
          return null;
        }
      }

      final llmDecoded = decodeMatrix(providersMatrix);
      final asrDecoded = decodeMatrix(asrProvidersMatrix);
      final ocrDecoded = decodeMatrix(ocrProvidersMatrix);

      apiConfigs = {
        'llm': {
          'baseUrl': await secureStorage.read(key: 'llm_base_url') ?? '',
          'apiKey': await secureStorage.read(key: 'llm_api_key') ?? '',
          'model': await secureStorage.read(key: 'llm_model') ?? '',
          'providers': ?llmDecoded,
          if (providersMatrix != null && providersMatrix.isNotEmpty)
            'providersMatrix': providersMatrix,
          if (activeProviderId != null && activeProviderId.isNotEmpty)
            'activeProviderId': activeProviderId,
        },
        'asr': {
          'provider': await secureStorage.read(key: 'asr_provider') ?? '',
          'baseUrl': await secureStorage.read(key: 'asr_base_url') ?? '',
          'apiKey': await secureStorage.read(key: 'asr_api_key') ?? '',
          'model': await secureStorage.read(key: 'asr_model') ?? '',
          'language': await secureStorage.read(key: 'asr_language') ?? '',
          'providers': ?asrDecoded,
          if (asrProvidersMatrix != null && asrProvidersMatrix.isNotEmpty)
            'providersMatrix': asrProvidersMatrix,
          if (asrActiveProviderId != null && asrActiveProviderId.isNotEmpty)
            'activeProviderId': asrActiveProviderId,
        },
        'ocr': {
          'provider': await secureStorage.read(key: 'ocr_provider') ?? '',
          'baseUrl': await secureStorage.read(key: 'ocr_base_url') ?? '',
          'apiKey': await secureStorage.read(key: 'ocr_api_key') ?? '',
          'model': await secureStorage.read(key: 'ocr_model') ?? '',
          'providers': ?ocrDecoded,
          if (ocrProvidersMatrix != null && ocrProvidersMatrix.isNotEmpty)
            'providersMatrix': ocrProvidersMatrix,
          if (ocrActiveProviderId != null && ocrActiveProviderId.isNotEmpty)
            'activeProviderId': ocrActiveProviderId,
          'ocr_concurrency': ?ocrConcurrency,
        },
      };
    }

    Map<String, dynamic>? promptConfigs;
    if (request.includePromptConfigs) {
      final promptRaw = await settingsRepo.get('llm_prompt_config');
      final extractorRaw =
          await settingsRepo.get('content_template_extractor_config');
      final dryRunRaw = await settingsRepo.get('llm_dry_run_enabled');

      promptConfigs = {
        if (promptRaw != null) 'llm_prompt_config': jsonDecode(promptRaw),
        if (extractorRaw != null)
          'content_template_extractor_config': jsonDecode(extractorRaw),
        if (dryRunRaw != null) 'llm_dry_run_enabled': dryRunRaw == 'true',
      };
    }

    Map<String, dynamic>? deviceConfigs;
    if (request.includeDeviceAndOutputConfigs) {
      final timingAppDefaults = await settingsRepo.get('timing_app_defaults');
      final timingPresetsList = await settingsRepo.get('timing_presets_list');
      final typingBlockPresetsList =
          await settingsRepo.get('typing_block_presets_list');
      final typingFeedback = await settingsRepo.get('typing_done_feedback');
      final qrMaxChunk = await settingsRepo.get('qr_max_chunk_size');
      final charReplacementRules =
          await settingsRepo.get('char_replacement_rules');
      final floatingOverlayEnabled =
          await settingsRepo.get('floating_overlay_enabled');
      final appFontScale = await settingsRepo.get('app_font_scale');

      deviceConfigs = {
        'timing_app_defaults': ?timingAppDefaults,
        'timing_presets_list': ?timingPresetsList,
        'typing_block_presets_list': ?typingBlockPresetsList,
        'typing_done_feedback': ?typingFeedback,
        'qr_max_chunk_size': ?qrMaxChunk,
        'char_replacement_rules': ?charReplacementRules,
        'floating_overlay_enabled': ?floatingOverlayEnabled,
        'app_font_scale': ?appFontScale,
      };
    }

    return EngineCBundleEnvelope(
      exportedAt: DateTime.now(),
      units: units,
      diagnoses: exportedDiags,
      diagnosisTags: exportedDiagTags.toList(),
      procedureTags: exportedProcTags.toList(),
      catalogTags: {
        for (final entry in exportedTagsByCatalog.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.toList(),
      },
      catalogs: allCatalogDefs
          .where((c) => effectiveCatalogTypes.contains(c.id))
          .toList(),
      apiConfigs: apiConfigs,
      promptConfigs: promptConfigs,
      deviceAndOutputConfigs: deviceConfigs,
    );
  }

  ContentTemplate _inlineContentTemplate(
    ContentTemplate content,
    Template structure,
    Map<String, List<FavoriteDiagnosis>> entriesByCatalog,
    Map<String, String> catalogNames,
    Set<String> includedCatalogTypes,
  ) {
    final slotByKey = {for (final s in structure.slots) s.key: s};

    String renderMention(CatalogMentionRef ref) {
      if (includedCatalogTypes.contains(ref.catalogType)) {
        return ref.token;
      }
      return _inlineCatalogRef(ref, entriesByCatalog, catalogNames);
    }

    String inlineText(String text) =>
        CatalogMentionHelper.replaceMentions(text, renderMention);

    ({String guidance, List<CatalogMentionRef> refs}) inlineGuidance(
      SlotContent slotContent,
      String? fallbackType,
    ) {
      final original = slotContent.guidance;
      var result = inlineText(original);

      final existingKeys = {
        for (final m in CatalogMentionHelper.parseMentions(original))
          '${m.catalogType}:${m.tag}',
      };

      final refs = <CatalogMentionRef>[
        ...slotContent.catalogRefs,
        if (slotContent.catalogRefs.isEmpty)
          for (final tag in slotContent.catalogTags)
            CatalogMentionRef(
              catalogType: (fallbackType == null || fallbackType.isEmpty)
                  ? 'diagnosis'
                  : fallbackType,
              tag: tag,
            ),
      ];

      final keptRefs = <CatalogMentionRef>[];
      for (final ref in refs) {
        final keep = includedCatalogTypes.contains(ref.catalogType);
        if (keep) keptRefs.add(ref);

        final key = '${ref.catalogType}:${ref.tag}';
        if (existingKeys.contains(key)) continue;

        final snippet = keep
            ? ref.token
            : _inlineCatalogRef(ref, entriesByCatalog, catalogNames);
        result = result.isEmpty ? snippet : '$result\n$snippet';
      }
      return (guidance: result, refs: keptRefs);
    }

    final slots = <String, SlotContent>{};
    for (final entry in content.slots.entries) {
      final inlined =
          inlineGuidance(entry.value, slotByKey[entry.key]?.catalogType);
      slots[entry.key] = SlotContent(
        examples: entry.value.examples,
        guidance: inlined.guidance,
        catalogRefs: inlined.refs,
        catalogTags: inlined.refs.map((r) => r.tag).toList(),
      );
    }

    return ContentTemplate(
      id: content.id,
      structureTemplateId: content.structureTemplateId,
      name: content.name,
      globalGuidance: inlineText(content.globalGuidance),
      fullExample: inlineText(content.fullExample),
      slots: slots,
      createdAt: content.createdAt,
      updatedAt: content.updatedAt,
    );
  }

  String _inlineCatalogRef(
    CatalogMentionRef ref,
    Map<String, List<FavoriteDiagnosis>> entriesByCatalog,
    Map<String, String> catalogNames,
  ) {
    final label = ref.label(catalogNames: catalogNames);
    final tag = ref.tag.trim().toLowerCase();
    final entries = (entriesByCatalog[ref.catalogType] ??
            const <FavoriteDiagnosis>[])
        .where((entry) =>
            entry.tags.any((t) => t.trim().toLowerCase() == tag))
        .toList();

    final buffer = StringBuffer('标准$label词条[${ref.tag}]');
    if (entries.isEmpty) {
      buffer.write('：（词库中暂无词条）');
    } else {
      buffer.write('：');
      buffer.write(entries
          .map((entry) =>
              entry.code.isNotEmpty ? '${entry.name} (${entry.code})' : entry.name)
          .join('、'));
    }
    return buffer.toString();
  }

  /// 导出为格式化 JSON 字符串
  Future<String> exportJsonString(EngineCExportRequest request) async {
    final envelope = await buildExportEnvelope(request);
    return const JsonEncoder.withIndent('  ').convert(envelope.toJson());
  }

  // ==========================================================================
  // 2. 格式归一化解析器 (Universal Envelope Parser - 兼容新旧所有 JSON 格式)
  // ==========================================================================

  static List<CatalogDefinition> _parseCatalogDefinitions(
    Map<String, dynamic> rawJson,
  ) {
    final raw = rawJson['catalogs'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => CatalogDefinition.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Map<String, List<String>> _parseCatalogTags(
    Map<String, dynamic> rawJson,
    List<String> diagnosisTags,
    List<String> procedureTags,
  ) {
    final raw = rawJson['catalog_tags'];
    if (raw is Map) {
      final result = <String, List<String>>{};
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is List) {
          final tags = value
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (tags.isNotEmpty) result[entry.key.toString()] = tags;
        }
      }
      if (result.isNotEmpty) return result;
    }
    return {
      if (diagnosisTags.isNotEmpty) 'diagnosis': diagnosisTags,
      if (procedureTags.isNotEmpty) 'procedure': procedureTags,
    };
  }

  /// 将任意合法的导出 JSON 解析为标准的 [EngineCBundleEnvelope]
  Future<EngineCBundleEnvelope> parseRawJsonToEnvelope(
    Map<String, dynamic> rawJson,
  ) async {
    final now = DateTime.now();

    // Case A: 标准 Engine C 格式 (`structure_units` 存在)
    if (rawJson['engine'] == 'medhistory_engine_c' ||
        rawJson.containsKey('structure_units')) {
      final rawUnits = (rawJson['structure_units'] as List?) ?? const [];
      final units = rawUnits
          .whereType<Map>()
          .map((u) => StructureGroundedUnit.fromJson(Map<String, dynamic>.from(u)))
          .toList();

      final rawDiags = (rawJson['catalog_entries'] as List?) ??
          (rawJson['favorite_diagnoses'] as List?) ??
          const [];
      final diags = rawDiags
          .whereType<Map>()
          .map((d) => FavoriteDiagnosis.fromMap(Map<String, dynamic>.from(d)))
          .toList();

      final rawTags = (rawJson['diagnosis_tags'] as List?) ?? const [];
      final tags = rawTags.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();

      final rawProcTags = (rawJson['procedure_tags'] as List?) ?? const [];
      final procTags = rawProcTags.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();

      return EngineCBundleEnvelope(
        engineVersion: rawJson['version']?.toString() ?? '2.0',
        exportedAt: DateTime.tryParse(rawJson['exported_at']?.toString() ?? '') ?? now,
        units: units,
        diagnoses: diags,
        diagnosisTags: tags,
        procedureTags: procTags,
        catalogTags: _parseCatalogTags(rawJson, tags, procTags),
        catalogs: _parseCatalogDefinitions(rawJson),
        apiConfigs: rawJson['api_configs'] is Map
            ? Map<String, dynamic>.from(rawJson['api_configs'] as Map)
            : null,
        promptConfigs: rawJson['prompt_configs'] is Map
            ? Map<String, dynamic>.from(rawJson['prompt_configs'] as Map)
            : null,
        deviceAndOutputConfigs: rawJson['device_and_output_configs'] is Map
            ? Map<String, dynamic>.from(rawJson['device_and_output_configs'] as Map)
            : null,
      );
    }

    // Case B: 旧版 BackupCenter 格式 (`templates` 数组 + `content_templates` 数组)
    if (rawJson.containsKey('templates') ||
        rawJson.containsKey('content_templates') ||
        rawJson.containsKey('catalog_entries') ||
        rawJson.containsKey('favorite_diagnoses') ||
        rawJson.containsKey('api_configs') ||
        rawJson.containsKey('prompt_configs') ||
        rawJson.containsKey('device_and_output_configs')) {
      final rawTemplates = (rawJson['templates'] as List?) ?? const [];
      final rawCts = (rawJson['content_templates'] as List?) ?? const [];

      final parsedCts = rawCts
          .whereType<Map>()
          .map((m) => ContentTemplate.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      final units = <StructureGroundedUnit>[];
      final handledStructureIds = <String>{};

      for (final item in rawTemplates) {
        if (item is Map) {
          final tmpl = Template.fromMap(Map<String, dynamic>.from(item));
          handledStructureIds.add(tmpl.id);
          final matchingCts = parsedCts
              .where((ct) => ct.structureTemplateId == tmpl.id)
              .toList();
          units.add(StructureGroundedUnit(
            structure: tmpl,
            hasPipeline: tmpl.pipeline.nodes.isNotEmpty,
            typingProfiles: tmpl.typingProfiles,
            contentTemplates: matchingCts,
          ));
        }
      }

      // 若旧版备份中存在孤立的 content_templates（未导出对应 structure），尝试用本地结构补齐根基
      final orphanCts = parsedCts
          .where((ct) => !handledStructureIds.contains(ct.structureTemplateId))
          .toList();
      if (orphanCts.isNotEmpty) {
        final localTemplates = await templateRepo.getAll();
        final byStructureId = <String, List<ContentTemplate>>{};
        for (final ct in orphanCts) {
          byStructureId.putIfAbsent(ct.structureTemplateId, () => []).add(ct);
        }
        for (final entry in byStructureId.entries) {
          final matchedLocal = localTemplates
                  .where((t) => t.id == entry.key)
                  .firstOrNull ??
              localTemplates.firstOrNull;
          if (matchedLocal != null) {
            units.add(StructureGroundedUnit(
              structure: matchedLocal,
              hasPipeline: false,
              typingProfiles: const [],
              contentTemplates: entry.value,
            ));
          }
        }
      }

      final rawDiags = (rawJson['catalog_entries'] as List?) ??
          (rawJson['favorite_diagnoses'] as List?) ??
          const [];
      final diags = rawDiags
          .whereType<Map>()
          .map((d) => FavoriteDiagnosis.fromMap(Map<String, dynamic>.from(d)))
          .toList();

      final rawTags = (rawJson['diagnosis_tags'] as List?) ?? const [];
      final tags = rawTags.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();

      final rawProcTags = (rawJson['procedure_tags'] as List?) ?? const [];
      final procTags = rawProcTags.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();

      return EngineCBundleEnvelope(
        engineVersion: '1.0-compat',
        exportedAt: now,
        units: units,
        diagnoses: diags,
        diagnosisTags: tags,
        procedureTags: procTags,
        catalogTags: _parseCatalogTags(rawJson, tags, procTags),
        catalogs: _parseCatalogDefinitions(rawJson),
        apiConfigs: rawJson['api_configs'] is Map
            ? Map<String, dynamic>.from(rawJson['api_configs'] as Map)
            : null,
        promptConfigs: rawJson['prompt_configs'] is Map
            ? Map<String, dynamic>.from(rawJson['prompt_configs'] as Map)
            : null,
        deviceAndOutputConfigs: rawJson['device_and_output_configs'] is Map
            ? Map<String, dynamic>.from(rawJson['device_and_output_configs'] as Map)
            : null,
      );
    }

    // Case C: 旧版单模板导出格式 (`exportType`: `structureOnly` / `structureWithPipeline` / `contentTemplate` / `pipelineOnly`)
    final exportType = rawJson['exportType'] as String?;
    if (exportType == 'structureOnly' || exportType == 'structureWithPipeline') {
      final tmplMap = Map<String, dynamic>.from(rawJson['template'] as Map);
      final tmpl = Template.fromMap(tmplMap);
      return EngineCBundleEnvelope(
        engineVersion: '1.0-legacy-template',
        exportedAt: now,
        units: [
          StructureGroundedUnit(
            structure: tmpl,
            hasPipeline:
                exportType == 'structureWithPipeline' && tmpl.pipeline.nodes.isNotEmpty,
            typingProfiles:
                exportType == 'structureWithPipeline' ? tmpl.typingProfiles : const [],
          ),
        ],
      );
    }

    if (exportType == 'contentTemplate') {
      final targetStructureName = rawJson['structureTemplateName'] as String?;
      final rawCt = Map<String, dynamic>.from(
          (rawJson['contentTemplate'] as Map?) ?? rawJson);
      final rawSlotMap = rawCt['slots'] is Map
          ? Map<String, dynamic>.from(rawCt['slots'] as Map)
          : (rawCt['slot_data'] is String
              ? Map<String, dynamic>.from(
                  jsonDecode(rawCt['slot_data'] as String) as Map)
              : <String, dynamic>{});

      final localTemplates = await templateRepo.getAll();
      Template? baseStructure = localTemplates
          .where((t) => t.name == targetStructureName)
          .firstOrNull;

      // 若本地无同名结构，根据内容模板的槽位 key 自动合成宿主结构骨架
      if (baseStructure == null) {
        var idx = 0;
        baseStructure = Template(
          name: targetStructureName ?? '导入文书类型',
          slots: [
            for (final key in rawSlotMap.keys)
              TemplateSlot(
                key: key,
                label: key,
                type: SlotType.text,
                order: idx++,
              ),
          ],
        );
      }

      final ct = ContentTemplate(
        structureTemplateId: baseStructure.id,
        name: rawCt['name'] as String? ?? '未命名内容模板',
        globalGuidance: rawCt['global_guidance'] as String? ?? '',
        fullExample: rawCt['full_example'] as String? ?? '',
        slots: {
          for (final e in rawSlotMap.entries)
            if (e.value is Map)
              e.key: SlotContent.fromJson(
                  Map<String, dynamic>.from(e.value as Map)),
        },
      );

      return EngineCBundleEnvelope(
        engineVersion: '1.0-legacy-ct',
        exportedAt: now,
        units: [
          StructureGroundedUnit(
            structure: baseStructure,
            hasPipeline: false,
            typingProfiles: const [],
            contentTemplates: [ct],
          ),
        ],
      );
    }

    // Case D: 直接裸 `Template.toMap()` JSON
    if (rawJson.containsKey('slots') && rawJson.containsKey('name')) {
      final tmpl = Template.fromMap(rawJson);
      return EngineCBundleEnvelope(
        engineVersion: '1.0-raw-template',
        exportedAt: now,
        units: [
          StructureGroundedUnit(
            structure: tmpl,
            hasPipeline: tmpl.pipeline.nodes.isNotEmpty,
            typingProfiles: tmpl.typingProfiles,
          ),
        ],
      );
    }

    throw const FormatException('无法识别的配置文本格式，未检测到文书类型或标准词条库数据');
  }

  // ==========================================================================
  // 3. 逐层树状比对与预检计划分析器 (Layered Tree Match & Fork Analyzer)
  // ==========================================================================

  /// 分析导入数据包，生成可视化的三层匹配与分叉执行计划 [EngineCImportPlan]
  Future<EngineCImportPlan> analyzeImport(Map<String, dynamic> rawJson) async {
    final envelope = await parseRawJsonToEnvelope(rawJson);
    final localTemplates = await templateRepo.getAll();
    final allLocalCts = await contentTemplateRepo.getAll();
    final allLocalDiags = await favoriteDiagnosisRepo.getAll();

    final unitPlans = <StructureUnitImportPlan>[];
    final claimedLocalIds = <String>{};

    // 逐个分析结构模板家族单元
    for (final unit in envelope.units) {
      final incStruct = unit.structure;

      // 同一份本地模板在一次导入里只认一次。先认 ID，ID 对不上再按名称。
      final unmatched = localTemplates
          .where((t) => !claimedLocalIds.contains(t.id))
          .toList();
      final matchedLocal = unmatched
              .where((t) => t.id == incStruct.id)
              .firstOrNull ??
          unmatched
              .where((t) => t.name.trim() == incStruct.name.trim())
              .firstOrNull;
      if (matchedLocal != null) claimedLocalIds.add(matchedLocal.id);

      if (matchedLocal == null) {
        // [第 1 层结果 A]：本地完全没有同名/同ID结构模板 -> 直接新建全套
        unitPlans.add(StructureUnitImportPlan(
          unit: unit,
          matchedLocalStructure: null,
          slotsSignatureMatched: false,
          structureAction: StructureMatchAction.createNew,
          pipelineAction: unit.hasPipeline
              ? PipelineMatchAction.applyToLocal
              : PipelineMatchAction.unchanged,
          typingProfilePlans: [
            for (final p in unit.typingProfiles)
              TypingProfilePlanItem(
                incoming: p,
                action: ChildItemMatchAction.createNew,
              ),
          ],
          contentTemplatePlans: [
            for (final ct in unit.contentTemplates)
              ContentTemplatePlanItem(
                incoming: ct,
                action: ChildItemMatchAction.createNew,
              ),
          ],
        ));
        continue;
      }

      // 本地存在同名/同ID结构模板，开始比对第 1 层：字段签名 (`slots`)
      final slotsMatch = EngineCDiffer.areSlotsSignatureEqual(
        matchedLocal.slots,
        incStruct.slots,
      );
      final diffSummary = EngineCDiffer.describeSlotDifferences(
        matchedLocal.slots,
        incStruct.slots,
      );

      if (!slotsMatch) {
        // [第 1 层结果 B]：结构模板同名，但字段签名不匹配！
        // 从第 1 层开始分叉：新建结构模板副本（例如 "住院病历 (副本)"），其下所有流程、方案、内容模板全部随新副本创建
        unitPlans.add(StructureUnitImportPlan(
          unit: unit,
          matchedLocalStructure: matchedLocal,
          slotsSignatureMatched: false,
          slotDiffSummary: diffSummary,
          structureAction: StructureMatchAction.forkAsCopy,
          pipelineAction: unit.hasPipeline
              ? PipelineMatchAction.applyToLocal
              : PipelineMatchAction.unchanged,
          typingProfilePlans: [
            for (final p in unit.typingProfiles)
              TypingProfilePlanItem(
                incoming: p,
                action: ChildItemMatchAction.createNew,
              ),
          ],
          contentTemplatePlans: [
            for (final ct in unit.contentTemplates)
              ContentTemplatePlanItem(
                incoming: ct,
                action: ChildItemMatchAction.createNew,
              ),
          ],
        ));
        continue;
      }

      // [第 1 层结果 C]：结构模板字段签名 100% 匹配！复用本地结构模板 `matchedLocal`，深入第 2 层比对各分支！
      // --- 分支 2A: 比对解析流程 (Pipeline) ---
      PipelineMatchAction pipelineAction = PipelineMatchAction.unchanged;
      if (unit.hasPipeline) {
        if (matchedLocal.pipeline.nodes.isEmpty) {
          pipelineAction = PipelineMatchAction.applyToLocal;
        } else if (EngineCDiffer.arePipelinesEqual(
            matchedLocal.pipeline, incStruct.pipeline)) {
          pipelineAction = PipelineMatchAction.unchanged;
        } else {
          // 默认替换为导入的新流程（UI 中允许用户切换为 keepLocal）
          pipelineAction = PipelineMatchAction.replaceLocal;
        }
      }

      // --- 分支 2B: 逐个比对键入方案 (TypingProfile) ---
      final profilePlans = <TypingProfilePlanItem>[];
      for (final incProfile in unit.typingProfiles) {
        final existingProf = matchedLocal.typingProfiles
            .where((p) => p.name.trim() == incProfile.name.trim())
            .firstOrNull;

        if (existingProf == null) {
          profilePlans.add(TypingProfilePlanItem(
            incoming: incProfile,
            action: ChildItemMatchAction.createNew,
          ));
        } else if (EngineCDiffer.areTypingProfilesEqual(
          existingProf,
          incProfile,
          matchedLocal.slots,
        )) {
          profilePlans.add(TypingProfilePlanItem(
            incoming: incProfile,
            existingLocal: existingProf,
            action: ChildItemMatchAction.identicalSkip,
          ));
        } else {
          // 若本地“默认”方案仅为空白初始态，而导入的“默认”方案有实际积木，则直接升级覆盖；否则在方案层新建副本！
          final action = EngineCDiffer.isTrivialDefaultProfile(existingProf)
              ? ChildItemMatchAction.overwriteLocalChild
              : ChildItemMatchAction.forkChildCopy;
          profilePlans.add(TypingProfilePlanItem(
            incoming: incProfile,
            existingLocal: existingProf,
            action: action,
          ));
        }
      }

      // --- 分支 2C: 逐个比对内容模板 (ContentTemplate) ---
      final localCtsForStruct = allLocalCts
          .where((c) => c.structureTemplateId == matchedLocal.id)
          .toList();
      final ctPlans = <ContentTemplatePlanItem>[];

      for (final incCt in unit.contentTemplates) {
        final existingCt = localCtsForStruct
            .where((c) => c.name.trim() == incCt.name.trim())
            .firstOrNull;

        if (existingCt == null) {
          ctPlans.add(ContentTemplatePlanItem(
            incoming: incCt,
            action: ChildItemMatchAction.createNew,
          ));
        } else if (EngineCDiffer.areContentTemplatesEqual(existingCt, incCt)) {
          ctPlans.add(ContentTemplatePlanItem(
            incoming: incCt,
            existingLocal: existingCt,
            action: ChildItemMatchAction.identicalSkip,
          ));
        } else {
          // 同名但内容有差异 -> 在内容模板这一层新建副本！
          ctPlans.add(ContentTemplatePlanItem(
            incoming: incCt,
            existingLocal: existingCt,
            action: ChildItemMatchAction.forkChildCopy,
          ));
        }
      }

      unitPlans.add(StructureUnitImportPlan(
        unit: unit,
        matchedLocalStructure: matchedLocal,
        slotsSignatureMatched: true,
        structureAction: StructureMatchAction.matchAndReuseLocal,
        pipelineAction: pipelineAction,
        typingProfilePlans: profilePlans,
        contentTemplatePlans: ctPlans,
      ));
    }

    // 分析独立常用标准词条与标签（诊断与手术等）
    final newDiags = <FavoriteDiagnosis>[];
    final mergedDiags = <FavoriteDiagnosis>[];
    var identicalDiags = 0;

    for (final incDiag in envelope.diagnoses) {
      final existing = allLocalDiags
          .where((d) =>
              d.catalogType == incDiag.catalogType &&
              d.code.trim() == incDiag.code.trim() &&
              d.name.trim() == incDiag.name.trim())
          .firstOrNull;

      if (existing == null) {
        newDiags.add(incDiag);
      } else {
        final missingTags = incDiag.tags
            .where((t) => !existing.tags.contains(t))
            .toList();
        final noteNeedsUpdate =
            existing.note.trim().isEmpty && incDiag.note.trim().isNotEmpty;
        if (missingTags.isNotEmpty || noteNeedsUpdate) {
          mergedDiags.add(existing.copyWith(
            tags: {...existing.tags, ...incDiag.tags}.toList(),
            note: noteNeedsUpdate ? incDiag.note : existing.note,
          ));
        } else {
          identicalDiags++;
        }
      }
    }

    final incomingTagsByCatalog = <String, Set<String>>{};
    for (final entry in envelope.catalogTags.entries) {
      incomingTagsByCatalog
          .putIfAbsent(entry.key, () => <String>{})
          .addAll(entry.value);
    }
    for (final d in envelope.diagnoses) {
      incomingTagsByCatalog
          .putIfAbsent(d.catalogType, () => <String>{})
          .addAll(d.tags);
    }

    final newTagsByCatalog = <String, List<String>>{};
    for (final entry in incomingTagsByCatalog.entries) {
      final existing = await catalogTagsRepo.getAll(entry.key);
      final fresh = entry.value
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty && !existing.contains(t))
          .toList();
      if (fresh.isNotEmpty) newTagsByCatalog[entry.key] = fresh;
    }

    final newDiagTags = newTagsByCatalog['diagnosis'] ?? const <String>[];
    final newProcTags = newTagsByCatalog['procedure'] ?? const <String>[];

    final diagPlan = DiagnosisImportPlan(
      newDiagnoses: newDiags,
      mergedTagDiagnoses: mergedDiags,
      identicalSkippedCount: identicalDiags,
      newTags: newDiagTags,
      newProcedureTags: newProcTags,
      newTagsByCatalog: newTagsByCatalog,
      enabled: envelope.diagnoses.isNotEmpty ||
          newTagsByCatalog.values.any((tags) => tags.isNotEmpty),
    );

    return EngineCImportPlan(
      envelope: envelope,
      unitPlans: unitPlans,
      diagnosisPlan: diagPlan,
      importApiConfigs: envelope.apiConfigs != null,
      importPromptConfigs: envelope.promptConfigs != null,
      importDeviceConfigs: envelope.deviceAndOutputConfigs != null,
    );
  }

  // ==========================================================================
  // 4. 计划执行器 (Plan Executor - 按决议精确入库与重映射外键)
  // ==========================================================================

  /// 执行经过预检确认的 [EngineCImportPlan]
  Future<EngineCImportExecutionResult> executeImportPlan(
    EngineCImportPlan plan,
  ) async {
    final result = EngineCImportExecutionResult();
    if (plan.envelope.catalogs.isNotEmpty) {
      final existing = await catalogRepo.getAll();
      final existingIds = existing.map((c) => c.id).toSet();
      for (final catalog in plan.envelope.catalogs) {
        if (!existingIds.contains(catalog.id)) {
          await catalogRepo.insert(catalog);
        }
      }
    }
    final allLocalTemplates = await templateRepo.getAll();
    final existingTemplateNames =
        allLocalTemplates.map((t) => t.name).toSet();
    final existingTemplateIds =
        allLocalTemplates.map((t) => t.id).toSet();

    // 1. 执行每个结构模板家族单元
    for (final unitPlan in plan.unitPlans) {
      if (unitPlan.structureAction == StructureMatchAction.skip) continue;

      try {
        final incStruct = unitPlan.unit.structure;

        if (unitPlan.structureAction == StructureMatchAction.createNew ||
            unitPlan.structureAction == StructureMatchAction.forkAsCopy) {
          // 决定新结构的 ID 与名称
          final isFork =
              unitPlan.structureAction == StructureMatchAction.forkAsCopy;
          final targetId =
              (isFork || existingTemplateIds.contains(incStruct.id))
                  ? _uuid.v4()
                  : incStruct.id;
          final targetName = EngineCDiffer.allocateForkName(
            incStruct.name,
            existingTemplateNames,
            suffixLabel: '副本',
          );
          existingTemplateNames.add(targetName);
          existingTemplateIds.add(targetId);

          // 收集要随新结构写入的键入方案
          final profilesToSave = unitPlan.typingProfilePlans
              .where((p) => p.action != ChildItemMatchAction.skip)
              .map((p) => p.incoming.duplicate(p.incoming.name))
              .toList();

          final newTemplate = Template(
            id: targetId,
            name: targetName,
            version: incStruct.version,
            slots: List.from(incStruct.slots),
            pipeline: unitPlan.unit.hasPipeline
                ? PipelineGraph.fromJsonString(incStruct.pipeline.toJsonString())
                : PipelineGraph(),
            typingProfiles: profilesToSave.isEmpty
                ? [TypingProfile(name: '默认')]
                : profilesToSave,
          );

          await templateRepo.insert(newTemplate);
          if (isFork) {
            result.forkedStructures++;
          } else {
            result.createdStructures++;
          }
          if (unitPlan.unit.hasPipeline) result.appliedPipelines++;
          result.addedTypingProfiles += profilesToSave.length;

          // 挂载所有选中的内容模板到新结构 ID 下
          final usedCtNames = <String>{};
          for (final ctPlan in unitPlan.contentTemplatePlans) {
            if (ctPlan.action == ChildItemMatchAction.skip) continue;
            final ctName = EngineCDiffer.allocateForkName(
              ctPlan.incoming.name,
              usedCtNames,
              suffixLabel: '副本',
            );
            usedCtNames.add(ctName);
            await contentTemplateRepo.insert(ContentTemplate(
              id: _uuid.v4(),
              structureTemplateId: targetId,
              name: ctName,
              globalGuidance: ctPlan.incoming.globalGuidance,
              fullExample: ctPlan.incoming.fullExample,
              slots: Map.of(ctPlan.incoming.slots),
            ));
            result.addedContentTemplates++;
          }
        } else if (unitPlan.structureAction ==
            StructureMatchAction.overwriteLocal) {
          // 强制覆盖本地结构模板（保留本地结构模板 ID，避免破坏历史病历消息关联）
          final local = unitPlan.matchedLocalStructure!;
          final updatedProfiles = unitPlan.unit.typingProfiles.isNotEmpty
              ? unitPlan.unit.typingProfiles
              : local.typingProfiles;
          final updatedPipeline = unitPlan.unit.hasPipeline
              ? incStruct.pipeline
              : local.pipeline;

          final updatedTemplate = local.copyWith(
            name: incStruct.name,
            version: incStruct.version,
            slots: List.from(incStruct.slots),
            pipeline: updatedPipeline,
            typingProfiles: updatedProfiles,
          );
          await templateRepo.update(updatedTemplate);
          result.overwrittenStructures++;

          // 内容模板按子计划入库
          await _executeContentTemplatePlansForStructure(
            local.id,
            unitPlan.contentTemplatePlans,
            result,
          );
        } else if (unitPlan.structureAction ==
            StructureMatchAction.matchAndReuseLocal) {
          // 复用本地结构模板，逐个分支处理第 2 层！
          final local = unitPlan.matchedLocalStructure!;
          var structureModified = false;

          // 2A: 解析流程
          PipelineGraph targetPipeline = local.pipeline;
          if (unitPlan.pipelineAction == PipelineMatchAction.applyToLocal ||
              unitPlan.pipelineAction == PipelineMatchAction.replaceLocal) {
            targetPipeline = PipelineGraph.fromJsonString(
                incStruct.pipeline.toJsonString());
            structureModified = true;
            result.appliedPipelines++;
          }

          // 2B: 键入方案（同名相同跳过，同名不同建方案副本，新增直接追加）
          final updatedProfiles = List<TypingProfile>.from(local.typingProfiles);
          final existingProfileNames =
              updatedProfiles.map((p) => p.name.trim()).toSet();

          for (final profPlan in unitPlan.typingProfilePlans) {
            switch (profPlan.action) {
              case ChildItemMatchAction.identicalSkip:
                result.skippedIdenticalProfiles++;
                break;
              case ChildItemMatchAction.skip:
                break;
              case ChildItemMatchAction.createNew:
                final newName = EngineCDiffer.allocateForkName(
                  profPlan.incoming.name,
                  existingProfileNames,
                );
                existingProfileNames.add(newName);
                updatedProfiles.add(profPlan.incoming.duplicate(newName));
                structureModified = true;
                result.addedTypingProfiles++;
                break;
              case ChildItemMatchAction.forkChildCopy:
                final forkName = EngineCDiffer.allocateForkName(
                  profPlan.incoming.name,
                  existingProfileNames,
                  suffixLabel: '副本',
                );
                existingProfileNames.add(forkName);
                updatedProfiles.add(profPlan.incoming.duplicate(forkName));
                structureModified = true;
                result.forkedTypingProfiles++;
                break;
              case ChildItemMatchAction.overwriteLocalChild:
                final idx = updatedProfiles.indexWhere(
                    (p) => p.id == profPlan.existingLocal?.id ||
                        p.name.trim() == profPlan.incoming.name.trim());
                if (idx >= 0) {
                  updatedProfiles[idx] = profPlan.incoming
                      .duplicate(profPlan.incoming.name);
                } else {
                  updatedProfiles
                      .add(profPlan.incoming.duplicate(profPlan.incoming.name));
                }
                structureModified = true;
                result.overwrittenTypingProfiles++;
                break;
            }
          }

          if (structureModified) {
            await templateRepo.update(local.copyWith(
              pipeline: targetPipeline,
              typingProfiles: updatedProfiles,
            ));
          }
          result.reusedStructures++;

          // 2C: 内容模板（挂载到复用结构下，同名不同直接建内容模板副本）
          await _executeContentTemplatePlansForStructure(
            local.id,
            unitPlan.contentTemplatePlans,
            result,
          );
        }
      } catch (e) {
        result.warnings.add('结构单元「${unitPlan.unit.structure.name}」导入异常: $e');
      }
    }

    // 2. 执行独立常用标准词条与标签导入
    if (plan.diagnosisPlan.enabled && plan.diagnosisPlan.hasAny) {
      try {
        for (final newDiag in plan.diagnosisPlan.newDiagnoses) {
          final existing = await favoriteDiagnosisRepo.findByCodeAndName(
            newDiag.code,
            newDiag.name,
            catalogType: newDiag.catalogType,
          );
          if (existing == null) {
            await favoriteDiagnosisRepo.insert(FavoriteDiagnosis(
              id: _uuid.v4(),
              catalogType: newDiag.catalogType,
              code: newDiag.code,
              name: newDiag.name,
              version: newDiag.version,
              note: newDiag.note,
              tags: List.from(newDiag.tags),
              order: newDiag.order,
            ));
            result.addedCatalogEntries++;
            if (newDiag.catalogType == 'procedure') {
              result.addedProcedures++;
            } else {
              result.addedDiagnoses++;
            }
          }
        }

        for (final mergedDiag in plan.diagnosisPlan.mergedTagDiagnoses) {
          await favoriteDiagnosisRepo.update(mergedDiag);
          result.mergedCatalogEntries++;
          if (mergedDiag.catalogType == 'procedure') {
            result.mergedProcedures++;
          } else {
            result.mergedDiagnoses++;
          }
        }

        for (final entry in plan.diagnosisPlan.newTagsByCatalog.entries) {
          for (final tag in entry.value) {
            await catalogTagsRepo.addTag(entry.key, tag);
          }
          result.addedCatalogTags += entry.value.length;
          if (entry.key == 'diagnosis') {
            result.addedDiagnosisTags = entry.value.length;
          } else if (entry.key == 'procedure') {
            result.addedProcedureTags = entry.value.length;
          }
        }
      } catch (e) {
        result.warnings.add('标准词条库导入异常: $e');
      }
    }

    // 3. 执行可选全局配置导入（API / Prompt / 外设时序）
    if (plan.importApiConfigs && plan.envelope.apiConfigs != null) {
      await _importApiConfigs(plan.envelope.apiConfigs!, result);
    }
    if (plan.importPromptConfigs && plan.envelope.promptConfigs != null) {
      await _importPromptConfigs(plan.envelope.promptConfigs!, result);
    }
    if (plan.importDeviceConfigs &&
        plan.envelope.deviceAndOutputConfigs != null) {
      await _importDeviceConfigs(
          plan.envelope.deviceAndOutputConfigs!, result);
    }

    return result;
  }

  Future<void> _executeContentTemplatePlansForStructure(
    String targetStructureId,
    List<ContentTemplatePlanItem> ctPlans,
    EngineCImportExecutionResult result,
  ) async {
    final existingCts =
        await contentTemplateRepo.getByStructure(targetStructureId);
    final existingCtNames = existingCts.map((c) => c.name.trim()).toSet();

    for (final ctPlan in ctPlans) {
      switch (ctPlan.action) {
        case ChildItemMatchAction.identicalSkip:
          result.skippedIdenticalContentTemplates++;
          break;
        case ChildItemMatchAction.skip:
          break;
        case ChildItemMatchAction.createNew:
          final newName = EngineCDiffer.allocateForkName(
            ctPlan.incoming.name,
            existingCtNames,
          );
          existingCtNames.add(newName);
          await contentTemplateRepo.insert(ContentTemplate(
            id: _uuid.v4(),
            structureTemplateId: targetStructureId,
            name: newName,
            globalGuidance: ctPlan.incoming.globalGuidance,
            fullExample: ctPlan.incoming.fullExample,
            slots: Map.of(ctPlan.incoming.slots),
          ));
          result.addedContentTemplates++;
          break;
        case ChildItemMatchAction.forkChildCopy:
          final forkName = EngineCDiffer.allocateForkName(
            ctPlan.incoming.name,
            existingCtNames,
            suffixLabel: '副本',
          );
          existingCtNames.add(forkName);
          await contentTemplateRepo.insert(ContentTemplate(
            id: _uuid.v4(),
            structureTemplateId: targetStructureId,
            name: forkName,
            globalGuidance: ctPlan.incoming.globalGuidance,
            fullExample: ctPlan.incoming.fullExample,
            slots: Map.of(ctPlan.incoming.slots),
          ));
          result.forkedContentTemplates++;
          break;
        case ChildItemMatchAction.overwriteLocalChild:
          final existing = ctPlan.existingLocal;
          if (existing == null) {
            await contentTemplateRepo.insert(ContentTemplate(
              id: _uuid.v4(),
              structureTemplateId: targetStructureId,
              name: ctPlan.incoming.name,
              globalGuidance: ctPlan.incoming.globalGuidance,
              fullExample: ctPlan.incoming.fullExample,
              slots: Map.of(ctPlan.incoming.slots),
            ));
          } else {
            await contentTemplateRepo.update(existing.copyWith(
              name: ctPlan.incoming.name,
              globalGuidance: ctPlan.incoming.globalGuidance,
              fullExample: ctPlan.incoming.fullExample,
              slots: Map.of(ctPlan.incoming.slots),
            ));
          }
          result.overwrittenContentTemplates++;
          break;
      }
    }
  }

  List<Map<String, dynamic>> _extractIncomingProviderMaps(dynamic raw) {
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  Future<int> _importLlmProviders(Map llm) async {
    final incomingMaps =
        _extractIncomingProviderMaps(llm['providers'] ?? llm['providersMatrix']);

    final legacyUrl = llm['baseUrl']?.toString();
    final legacyKey = llm['apiKey']?.toString();
    final legacyModel = llm['model']?.toString();

    final currentRaw = await secureStorage.read(key: 'llm_providers_matrix_v1');
    List<Map<String, dynamic>> currentList =
        _extractIncomingProviderMaps(currentRaw);
    if (currentList.isEmpty) {
      currentList = LlmProviderPresets.builtIn.map((p) => p.toJson()).toList();
    }

    var configuredCount = 0;
    if (incomingMaps.isNotEmpty) {
      final currentMap = {
        for (int i = 0; i < currentList.length; i++)
          currentList[i]['id']?.toString() ?? '': i
      };

      for (final inc in incomingMaps) {
        final id = inc['id']?.toString();
        if (id == null || id.isEmpty) continue;

        if (currentMap.containsKey(id)) {
          final idx = currentMap[id]!;
          final existing = currentList[idx];
          final merged = Map<String, dynamic>.from(existing);

          if (inc['apiKey'] != null &&
              inc['apiKey'].toString().trim().isNotEmpty) {
            merged['apiKey'] = inc['apiKey'].toString();
          }
          if (inc['baseUrl'] != null &&
              inc['baseUrl'].toString().trim().isNotEmpty) {
            merged['baseUrl'] = inc['baseUrl'].toString();
          }
          if (inc['selectedModel'] != null &&
              inc['selectedModel'].toString().trim().isNotEmpty) {
            merged['selectedModel'] = inc['selectedModel'].toString();
          }
          if (inc['customModels'] is List) {
            final models = Set<String>.from(
                (merged['customModels'] as List?)?.map((e) => e.toString()) ??
                    const []);
            models.addAll((inc['customModels'] as List).map((e) => e.toString()));
            merged['customModels'] = models.toList();
          }
          if (inc.containsKey('isEnabled')) {
            merged['isEnabled'] = inc['isEnabled'] == true;
          }
          currentList[idx] = merged;
          if (merged['apiKey'] != null &&
              merged['apiKey'].toString().trim().isNotEmpty) {
            configuredCount++;
          }
        } else {
          currentList.add(inc);
          currentMap[id] = currentList.length - 1;
          if (inc['apiKey'] != null &&
              inc['apiKey'].toString().trim().isNotEmpty) {
            configuredCount++;
          }
        }
      }

      await secureStorage.write(
        key: 'llm_providers_matrix_v1',
        value: jsonEncode(currentList),
      );

      final activeId = llm['activeProviderId']?.toString();
      final targetActiveId = (activeId != null && currentMap.containsKey(activeId))
          ? activeId
          : (currentList.any((p) => (p['apiKey']?.toString() ?? '').trim().isNotEmpty)
              ? currentList.firstWhere(
                  (p) => (p['apiKey']?.toString() ?? '').trim().isNotEmpty)['id']
                  ?.toString() ?? 'deepseek'
              : 'deepseek');

      await secureStorage.write(
          key: 'llm_active_provider_id_v1', value: targetActiveId);
      final activeIdx = currentMap[targetActiveId];
      if (activeIdx != null) {
        final activeConfig = currentList[activeIdx];
        await secureStorage.write(
            key: 'llm_base_url',
            value: activeConfig['baseUrl']?.toString() ?? '');
        await secureStorage.write(
            key: 'llm_api_key', value: activeConfig['apiKey']?.toString() ?? '');
        await secureStorage.write(
            key: 'llm_model',
            value: activeConfig['selectedModel']?.toString() ?? '');
      }
    } else {
      if (legacyUrl != null) {
        await secureStorage.write(key: 'llm_base_url', value: legacyUrl);
      }
      if (legacyKey != null) {
        await secureStorage.write(key: 'llm_api_key', value: legacyKey);
      }
      if (legacyModel != null) {
        await secureStorage.write(key: 'llm_model', value: legacyModel);
      }
      await secureStorage.write(key: 'llm_providers_matrix_v1', value: '');
      await secureStorage.write(key: 'llm_active_provider_id_v1', value: '');
      configuredCount = legacyKey != null && legacyKey.trim().isNotEmpty ? 1 : 0;
    }
    return configuredCount;
  }

  Future<int> _importAsrProviders(Map asr) async {
    final incomingMaps =
        _extractIncomingProviderMaps(asr['providers'] ?? asr['providersMatrix']);

    final legacyProvider = asr['provider']?.toString();
    final legacyUrl = asr['baseUrl']?.toString();
    final legacyKey = asr['apiKey']?.toString();
    final legacyModel = asr['model']?.toString();
    final legacyLang = asr['language']?.toString();

    final currentRaw = await secureStorage.read(key: 'asr_providers_matrix_v1');
    List<Map<String, dynamic>> currentList =
        _extractIncomingProviderMaps(currentRaw);
    if (currentList.isEmpty) {
      currentList = AsrProviderPresets.builtIn.map((p) => p.toJson()).toList();
    }

    var configuredCount = 0;
    if (incomingMaps.isNotEmpty) {
      final currentMap = {
        for (int i = 0; i < currentList.length; i++)
          currentList[i]['id']?.toString() ?? '': i
      };

      for (final inc in incomingMaps) {
        final id = inc['id']?.toString();
        if (id == null || id.isEmpty) continue;

        if (currentMap.containsKey(id)) {
          final idx = currentMap[id]!;
          final existing = currentList[idx];
          final merged = Map<String, dynamic>.from(existing);

          if (inc['apiKey'] != null &&
              inc['apiKey'].toString().trim().isNotEmpty) {
            merged['apiKey'] = inc['apiKey'].toString();
          }
          if (inc['baseUrl'] != null &&
              inc['baseUrl'].toString().trim().isNotEmpty) {
            merged['baseUrl'] = inc['baseUrl'].toString();
          }
          if (inc['selectedModel'] != null &&
              inc['selectedModel'].toString().trim().isNotEmpty) {
            merged['selectedModel'] = inc['selectedModel'].toString();
          }
          if (inc['language'] != null &&
              inc['language'].toString().trim().isNotEmpty) {
            merged['language'] = inc['language'].toString();
          }
          if (inc['customModels'] is List) {
            final models = Set<String>.from(
                (merged['customModels'] as List?)?.map((e) => e.toString()) ??
                    const []);
            models.addAll((inc['customModels'] as List).map((e) => e.toString()));
            merged['customModels'] = models.toList();
          }
          if (inc.containsKey('isEnabled')) {
            merged['isEnabled'] = inc['isEnabled'] == true;
          }
          currentList[idx] = merged;
          if (merged['apiKey'] != null &&
              merged['apiKey'].toString().trim().isNotEmpty) {
            configuredCount++;
          }
        } else {
          currentList.add(inc);
          currentMap[id] = currentList.length - 1;
          if (inc['apiKey'] != null &&
              inc['apiKey'].toString().trim().isNotEmpty) {
            configuredCount++;
          }
        }
      }

      await secureStorage.write(
        key: 'asr_providers_matrix_v1',
        value: jsonEncode(currentList),
      );

      final activeId = asr['activeProviderId']?.toString();
      final targetActiveId = (activeId != null && currentMap.containsKey(activeId))
          ? activeId
          : (currentList.any((p) => (p['apiKey']?.toString() ?? '').trim().isNotEmpty)
              ? currentList.firstWhere(
                  (p) => (p['apiKey']?.toString() ?? '').trim().isNotEmpty)['id']
                  ?.toString() ?? 'zhipu'
              : 'zhipu');

      await secureStorage.write(
          key: 'asr_active_provider_id_v1', value: targetActiveId);
      final activeIdx = currentMap[targetActiveId];
      if (activeIdx != null) {
        final activeConfig = currentList[activeIdx];
        await secureStorage.write(
            key: 'asr_provider',
            value: activeConfig['id']?.toString() ?? '');
        await secureStorage.write(
            key: 'asr_base_url',
            value: activeConfig['baseUrl']?.toString() ?? '');
        await secureStorage.write(
            key: 'asr_api_key', value: activeConfig['apiKey']?.toString() ?? '');
        await secureStorage.write(
            key: 'asr_model',
            value: activeConfig['selectedModel']?.toString() ?? '');
        await secureStorage.write(
            key: 'asr_language',
            value: activeConfig['language']?.toString() ?? 'zh');
      }
    } else {
      if (legacyProvider != null) {
        await secureStorage.write(key: 'asr_provider', value: legacyProvider);
      }
      if (legacyUrl != null) {
        await secureStorage.write(key: 'asr_base_url', value: legacyUrl);
      }
      if (legacyKey != null) {
        await secureStorage.write(key: 'asr_api_key', value: legacyKey);
      }
      if (legacyModel != null) {
        await secureStorage.write(key: 'asr_model', value: legacyModel);
      }
      if (legacyLang != null) {
        await secureStorage.write(key: 'asr_language', value: legacyLang);
      }
      await secureStorage.write(key: 'asr_providers_matrix_v1', value: '');
      await secureStorage.write(key: 'asr_active_provider_id_v1', value: '');
      configuredCount = legacyKey != null && legacyKey.trim().isNotEmpty ? 1 : 0;
    }
    return configuredCount;
  }

  Future<int> _importOcrProviders(Map ocr, Map apis) async {
    final incomingMaps =
        _extractIncomingProviderMaps(ocr['providers'] ?? ocr['providersMatrix']);

    final legacyProvider = ocr['provider']?.toString();
    final legacyUrl = ocr['baseUrl']?.toString();
    final legacyKey = ocr['apiKey']?.toString();
    final legacyModel = ocr['model']?.toString();

    final currentRaw = await secureStorage.read(key: 'ocr_providers_matrix_v1');
    List<Map<String, dynamic>> currentList =
        _extractIncomingProviderMaps(currentRaw);
    if (currentList.isEmpty) {
      currentList = OcrProviderPresets.builtIn.map((p) => p.toJson()).toList();
    }

    var configuredCount = 0;
    if (incomingMaps.isNotEmpty) {
      final currentMap = {
        for (int i = 0; i < currentList.length; i++)
          currentList[i]['id']?.toString() ?? '': i
      };

      for (final inc in incomingMaps) {
        final id = inc['id']?.toString();
        if (id == null || id.isEmpty) continue;

        if (currentMap.containsKey(id)) {
          final idx = currentMap[id]!;
          final existing = currentList[idx];
          final merged = Map<String, dynamic>.from(existing);

          if (inc['apiKey'] != null &&
              inc['apiKey'].toString().trim().isNotEmpty) {
            merged['apiKey'] = inc['apiKey'].toString();
          }
          if (inc['baseUrl'] != null &&
              inc['baseUrl'].toString().trim().isNotEmpty) {
            merged['baseUrl'] = inc['baseUrl'].toString();
          }
          if (inc['selectedModel'] != null &&
              inc['selectedModel'].toString().trim().isNotEmpty) {
            merged['selectedModel'] = inc['selectedModel'].toString();
          }
          if (inc['customModels'] is List) {
            final models = Set<String>.from(
                (merged['customModels'] as List?)?.map((e) => e.toString()) ??
                    const []);
            models.addAll((inc['customModels'] as List).map((e) => e.toString()));
            merged['customModels'] = models.toList();
          }
          if (inc.containsKey('isEnabled')) {
            merged['isEnabled'] = inc['isEnabled'] == true;
          }
          currentList[idx] = merged;
          if (merged['apiKey'] != null &&
              merged['apiKey'].toString().trim().isNotEmpty) {
            configuredCount++;
          }
        } else {
          currentList.add(inc);
          currentMap[id] = currentList.length - 1;
          if (inc['apiKey'] != null &&
              inc['apiKey'].toString().trim().isNotEmpty) {
            configuredCount++;
          }
        }
      }

      await secureStorage.write(
        key: 'ocr_providers_matrix_v1',
        value: jsonEncode(currentList),
      );

      final activeId = ocr['activeProviderId']?.toString();
      final targetActiveId = (activeId != null && currentMap.containsKey(activeId))
          ? activeId
          : (currentList.any((p) => (p['apiKey']?.toString() ?? '').trim().isNotEmpty)
              ? currentList.firstWhere(
                  (p) => (p['apiKey']?.toString() ?? '').trim().isNotEmpty)['id']
                  ?.toString() ?? 'modelbest'
              : 'modelbest');

      await secureStorage.write(
          key: 'ocr_active_provider_id_v1', value: targetActiveId);
      final activeIdx = currentMap[targetActiveId];
      if (activeIdx != null) {
        final activeConfig = currentList[activeIdx];
        await secureStorage.write(
            key: 'ocr_provider',
            value: activeConfig['id']?.toString() ?? '');
        await secureStorage.write(
            key: 'ocr_base_url',
            value: activeConfig['baseUrl']?.toString() ?? '');
        await secureStorage.write(
            key: 'ocr_api_key', value: activeConfig['apiKey']?.toString() ?? '');
        await secureStorage.write(
            key: 'ocr_model',
            value: activeConfig['selectedModel']?.toString() ?? '');
      }
    } else {
      if (legacyProvider != null) {
        await secureStorage.write(key: 'ocr_provider', value: legacyProvider);
      }
      if (legacyUrl != null) {
        await secureStorage.write(key: 'ocr_base_url', value: legacyUrl);
      }
      if (legacyKey != null) {
        await secureStorage.write(key: 'ocr_api_key', value: legacyKey);
      }
      if (legacyModel != null) {
        await secureStorage.write(key: 'ocr_model', value: legacyModel);
      }
      await secureStorage.write(key: 'ocr_providers_matrix_v1', value: '');
      await secureStorage.write(key: 'ocr_active_provider_id_v1', value: '');
      configuredCount = legacyKey != null && legacyKey.trim().isNotEmpty ? 1 : 0;
    }

    final concurrency = ocr['ocr_concurrency'] ?? apis['ocr_concurrency'];
    if (concurrency != null) {
      await settingsRepo.set('ocr_concurrency', concurrency.toString());
    }

    return configuredCount;
  }

  Future<void> _importApiConfigs(
    Map<String, dynamic> apis,
    EngineCImportExecutionResult result,
  ) async {
    try {
      if (apis['llm'] is Map) {
        result.importedLlmProviders =
            await _importLlmProviders(apis['llm'] as Map);
      }
      // Publishing credentials from old backups are intentionally ignored.
      if (apis['asr'] is Map) {
        result.importedAsrProviders =
            await _importAsrProviders(apis['asr'] as Map);
      }
      if (apis['ocr'] is Map) {
        result.importedOcrProviders =
            await _importOcrProviders(apis['ocr'] as Map, apis);
      }
      result.importedApiConfigs = true;
    } catch (e) {
      result.warnings.add('API 配置导入异常: $e');
    }
  }

  Future<void> _importPromptConfigs(
    Map<String, dynamic> prompts,
    EngineCImportExecutionResult result,
  ) async {
    try {
      if (prompts.containsKey('llm_prompt_config')) {
        await settingsRepo.set(
            'llm_prompt_config', jsonEncode(prompts['llm_prompt_config']));
      }
      if (prompts.containsKey('content_template_extractor_config')) {
        await settingsRepo.set('content_template_extractor_config',
            jsonEncode(prompts['content_template_extractor_config']));
      }
      if (prompts.containsKey('llm_dry_run_enabled')) {
        await settingsRepo.set('llm_dry_run_enabled',
            prompts['llm_dry_run_enabled'] == true ? 'true' : 'false');
      }
      result.importedPromptConfigs = true;
    } catch (e) {
      result.warnings.add('Prompt 提示词配置导入异常: $e');
    }
  }

  Future<void> _importDeviceConfigs(
    Map<String, dynamic> devs,
    EngineCImportExecutionResult result,
  ) async {
    try {
      if (devs.containsKey('timing_app_defaults')) {
        await settingsRepo.set(
            'timing_app_defaults', devs['timing_app_defaults'].toString());
      }
      if (devs.containsKey('timing_presets_list')) {
        await settingsRepo.set(
            'timing_presets_list', devs['timing_presets_list'].toString());
      }
      if (devs.containsKey('typing_block_presets_list')) {
        await settingsRepo.set('typing_block_presets_list',
            devs['typing_block_presets_list'].toString());
      }
      if (devs.containsKey('typing_done_feedback')) {
        await settingsRepo.set(
            'typing_done_feedback', devs['typing_done_feedback'].toString());
      }
      if (devs.containsKey('qr_max_chunk_size')) {
        await settingsRepo.set(
            'qr_max_chunk_size', devs['qr_max_chunk_size'].toString());
      }
      if (devs.containsKey('char_replacement_rules')) {
        await settingsRepo.set('char_replacement_rules',
            devs['char_replacement_rules'].toString());
      }
      if (devs.containsKey('floating_overlay_enabled')) {
        await settingsRepo.set('floating_overlay_enabled',
            devs['floating_overlay_enabled'].toString());
      }
      if (devs.containsKey('app_font_scale')) {
        await settingsRepo.set(
            'app_font_scale', devs['app_font_scale'].toString());
      }
      result.importedDeviceConfigs = true;
    } catch (e) {
      result.warnings.add('外设时序与二维码配置导入异常: $e');
    }
  }
}

/// Engine C 全局 Provider
final templateBundleEngineProvider = Provider<TemplateBundleEngine>((ref) {
  return TemplateBundleEngine(
    templateRepo: ref.read(templateRepositoryProvider),
    contentTemplateRepo: ref.read(contentTemplateRepositoryProvider),
    favoriteDiagnosisRepo: ref.read(favoriteDiagnosisRepositoryProvider),
    catalogRepo: ref.read(catalogRepositoryProvider),
    catalogTagsRepo: ref.read(catalogTagsRepositoryProvider),
    settingsRepo: ref.read(settingsRepositoryProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
});
