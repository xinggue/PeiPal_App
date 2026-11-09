import 'dart:convert';

import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/favorite_diagnosis.dart';
import '../../../domain/models/pipeline_graph.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_profile.dart';

/// 引擎 C 导出选项：定义针对单个结构模板家族（Structure Family）的细粒度选择
class StructureFamilyExportSelection {
  final String templateId;

  /// 是否包含 AI 阶段解析流程 (Pipeline)
  final bool includePipeline;

  /// 选中的键入方案 ID 集合（若为 null 表示全部包含；若为空集合表示不包含任何自定义键入方案）
  final Set<String>? selectedTypingProfileIds;

  /// 选中的关联内容模板 ID 集合（若为 null 表示全部包含；若为空集合表示不包含）
  final Set<String>? selectedContentTemplateIds;

  /// 是否自动扫描并附带所选内容模板绑定的常用诊断词条 (`catalogTags`)
  final bool includeLinkedDiagnoses;

  const StructureFamilyExportSelection({
    required this.templateId,
    this.includePipeline = true,
    this.selectedTypingProfileIds,
    this.selectedContentTemplateIds,
    this.includeLinkedDiagnoses = true,
  });

  StructureFamilyExportSelection copyWith({
    bool? includePipeline,
    Set<String>? selectedTypingProfileIds,
    Set<String>? selectedContentTemplateIds,
    bool? includeLinkedDiagnoses,
  }) =>
      StructureFamilyExportSelection(
        templateId: templateId,
        includePipeline: includePipeline ?? this.includePipeline,
        selectedTypingProfileIds:
            selectedTypingProfileIds ?? this.selectedTypingProfileIds,
        selectedContentTemplateIds:
            selectedContentTemplateIds ?? this.selectedContentTemplateIds,
        includeLinkedDiagnoses:
            includeLinkedDiagnoses ?? this.includeLinkedDiagnoses,
      );
}

/// 引擎 C 统一导出请求配置
class EngineCExportRequest {
  /// 要导出的结构模板家族列表（每一项强制包含其结构模板骨架）
  final List<StructureFamilyExportSelection> families;

  /// 独立导出/额外导出的常用词条过滤：
  /// - [includeAllDiagnoses]: true 时导出全部常用标准词条与标签（含诊断及手术操作）
  /// - [catalogTypes]: 选中的词条类别（若为空则默认包含 diagnosis 与 procedure）
  /// - [selectedDiagnosisTags]: 按标签筛选导出
  /// - [selectedDiagnosisIds]: 按指定 ID 筛选导出
  final bool includeAllDiagnoses;
  final Set<String> catalogTypes;
  final Set<String> selectedDiagnosisTags;
  final Set<String> selectedDiagnosisIds;

  /// 全局配置项（供导入导出中心全量备份使用）
  final bool includeApiConfigs;
  final bool includePromptConfigs;
  final bool includeDeviceAndOutputConfigs;

  const EngineCExportRequest({
    this.families = const [],
    this.includeAllDiagnoses = false,
    this.catalogTypes = const {},
    this.selectedDiagnosisTags = const {},
    this.selectedDiagnosisIds = const {},
    this.includeApiConfigs = false,
    this.includePromptConfigs = false,
    this.includeDeviceAndOutputConfigs = false,
  });

  bool get hasAnySelected =>
      families.isNotEmpty ||
      includeAllDiagnoses ||
      selectedDiagnosisTags.isNotEmpty ||
      selectedDiagnosisIds.isNotEmpty ||
      includeApiConfigs ||
      includePromptConfigs ||
      includeDeviceAndOutputConfigs;
}

/// 挂载在结构模板根基之上的完整家族数据包（Engine C 单元）
class StructureGroundedUnit {
  /// 强制附带的完整结构模板定义（含 slots）
  final Template structure;

  /// 本次打包是否携带了解析流程
  final bool hasPipeline;

  /// 本次打包携带的键入方案列表
  final List<TypingProfile> typingProfiles;

  /// 本次打包携带的配套内容模板列表
  final List<ContentTemplate> contentTemplates;

  const StructureGroundedUnit({
    required this.structure,
    required this.hasPipeline,
    this.typingProfiles = const [],
    this.contentTemplates = const [],
  });

  Map<String, dynamic> toJson() => {
        'structure': {
          'id': structure.id,
          'name': structure.name,
          'version': structure.version,
          'slots': structure.slots.map((s) => s.toJson()).toList(),
          'created_at': structure.createdAt.toIso8601String(),
          'updated_at': structure.updatedAt.toIso8601String(),
        },
        'has_pipeline': hasPipeline,
        if (hasPipeline && structure.pipeline.nodes.isNotEmpty)
          'pipeline': jsonDecode(structure.pipeline.toJsonString()),
        'typing_profiles': typingProfiles.map((p) => p.toJson()).toList(),
        'content_templates': contentTemplates
            .map((ct) => {
                  'id': ct.id,
                  'structure_template_id': ct.structureTemplateId,
                  'name': ct.name,
                  'global_guidance': ct.globalGuidance,
                  'full_example': ct.fullExample,
                  'slots': {
                    for (final e in ct.slots.entries)
                      if (!e.value.isEmpty) e.key: e.value.toJson(),
                  },
                  'created_at': ct.createdAt.toIso8601String(),
                  'updated_at': ct.updatedAt.toIso8601String(),
                })
            .toList(),
      };

  factory StructureGroundedUnit.fromJson(Map<String, dynamic> json) {
    final structMap = Map<String, dynamic>.from(json['structure'] as Map);
    final rawSlots = (structMap['slots'] as List?) ?? const [];
    final slots = rawSlots
        .map((s) => TemplateSlot.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();

    final hasPipeline = json['has_pipeline'] as bool? ??
        (json['pipeline'] != null);
    final rawPipeline = json['pipeline'];
    final pipeline = (hasPipeline && rawPipeline is Map)
        ? PipelineGraph.fromJsonString(jsonEncode(rawPipeline))
        : PipelineGraph();

    final rawProfiles = (json['typing_profiles'] as List?) ?? const [];
    final profiles = rawProfiles
        .map((p) => TypingProfile.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();

    final structure = Template(
      id: structMap['id'] as String?,
      name: structMap['name'] as String? ?? '未命名文书类型',
      version: structMap['version'] as String? ?? '1.0',
      slots: slots,
      pipeline: pipeline,
      typingProfiles: profiles.isEmpty ? [TypingProfile(name: '默认')] : profiles,
      createdAt: structMap['created_at'] != null
          ? DateTime.tryParse(structMap['created_at'].toString())
          : null,
      updatedAt: structMap['updated_at'] != null
          ? DateTime.tryParse(structMap['updated_at'].toString())
          : null,
    );

    final rawCts = (json['content_templates'] as List?) ?? const [];
    final cts = <ContentTemplate>[];
    for (final item in rawCts) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final rawSlotMap = m['slots'] is Map
            ? Map<String, dynamic>.from(m['slots'] as Map)
            : (m['slot_data'] is String
                ? Map<String, dynamic>.from(
                    jsonDecode(m['slot_data'] as String) as Map)
                : <String, dynamic>{});
        cts.add(ContentTemplate(
          id: m['id'] as String?,
          structureTemplateId: structure.id,
          name: m['name'] as String? ?? '未命名内容模板',
          globalGuidance: m['global_guidance'] as String? ?? '',
          fullExample: m['full_example'] as String? ?? '',
          slots: {
            for (final e in rawSlotMap.entries)
              if (e.value is Map)
                e.key: SlotContent.fromJson(
                    Map<String, dynamic>.from(e.value as Map)),
          },
          createdAt: m['created_at'] != null
              ? DateTime.tryParse(m['created_at'].toString())
              : null,
          updatedAt: m['updated_at'] != null
              ? DateTime.tryParse(m['updated_at'].toString())
              : null,
        ));
      }
    }

    return StructureGroundedUnit(
      structure: structure,
      hasPipeline: hasPipeline && pipeline.nodes.isNotEmpty,
      typingProfiles: profiles,
      contentTemplates: cts,
    );
  }
}

/// 引擎 C 标准交换信封（兼容单模板、全套家族、独立诊断库及全量系统备份）
class EngineCBundleEnvelope {
  final String engineVersion;
  final DateTime exportedAt;

  /// 以结构模板为根基的家族单元列表
  final List<StructureGroundedUnit> units;

  /// 通用词条与标签集合
  final List<FavoriteDiagnosis> diagnoses;
  final List<String> diagnosisTags;
  final List<String> procedureTags;

  /// Generic tags keyed by catalog id (new format).
  final Map<String, List<String>> catalogTags;

  /// Catalog definitions (name/icon/source) for portable custom catalogs.
  final List<CatalogDefinition> catalogs;

  /// 可选全局配置（用于全量备份）
  final Map<String, dynamic>? apiConfigs;
  final Map<String, dynamic>? promptConfigs;
  final Map<String, dynamic>? deviceAndOutputConfigs;

  /// 兼容极端旧版格式（仅导出了无结构包裹的孤立流程或孤立内容模板）
  final Map<String, dynamic>? legacyOrphanPayload;

  const EngineCBundleEnvelope({
    this.engineVersion = '2.0',
    required this.exportedAt,
    this.units = const [],
    this.diagnoses = const [],
    this.diagnosisTags = const [],
    this.procedureTags = const [],
    this.catalogTags = const {},
    this.catalogs = const [],
    this.apiConfigs,
    this.promptConfigs,
    this.deviceAndOutputConfigs,
    this.legacyOrphanPayload,
  });

  Map<String, dynamic> toJson() => {
        'engine': 'medhistory_engine_c',
        'version': engineVersion,
        'exported_at': exportedAt.toIso8601String(),
        if (units.isNotEmpty)
          'structure_units': units.map((u) => u.toJson()).toList(),
        if (diagnoses.isNotEmpty) ...{
          // Legacy key for old importers.
          'favorite_diagnoses': diagnoses.map((d) => d.toMap()).toList(),
          // New generic key.
          'catalog_entries': diagnoses.map((d) => d.toMap()).toList(),
        },
        if (diagnosisTags.isNotEmpty) 'diagnosis_tags': diagnosisTags,
        if (procedureTags.isNotEmpty) 'procedure_tags': procedureTags,
        if (catalogTags.isNotEmpty) 'catalog_tags': catalogTags,
        if (catalogs.isNotEmpty)
          'catalogs': catalogs.map((c) => c.toMap()).toList(),
        if (apiConfigs != null) 'api_configs': apiConfigs,
        if (promptConfigs != null) 'prompt_configs': promptConfigs,
        if (deviceAndOutputConfigs != null)
          'device_and_output_configs': deviceAndOutputConfigs,
      };
}

// ============================================================================
// 逐层匹配与分叉决议模型 (Layered Tree Match & Fork Resolution Models)
// ============================================================================

/// 第一层：结构模板骨架匹配动作
enum StructureMatchAction {
  /// 本地无同名/同ID结构模板 -> 直接新建该结构模板
  createNew,

  /// 本地已有同名/同ID结构模板，且字段列表 (slots) 签名完全匹配 -> 复用本地结构模板，继续深入比对子层
  matchAndReuseLocal,

  /// 本地已有同名/同ID结构模板，但字段列表 (slots) 签名不一致 -> 从第1层开始分叉，新建结构模板副本（含其全套子项）
  forkAsCopy,

  /// 用户主动选择：用导入的结构字段强行覆盖更新本地同ID/同名结构模板
  overwriteLocal,

  /// 跳过此结构单元
  skip,
}

/// 第二层（分支 A）：解析流程匹配动作
enum PipelineMatchAction {
  /// 导入包未携带流程，或与本地流程完全一致 -> 无需变更
  unchanged,

  /// 本地尚无解析流程 -> 直接写入导入的解析流程
  applyToLocal,

  /// 本地已有不同的解析流程 -> 替换为导入的解析流程
  replaceLocal,

  /// 本地已有不同的解析流程 -> 保留本地原流程，忽略导入流程
  keepLocal,
}

/// 第二层（分支 B & C）：子组件（键入方案 / 内容模板）匹配动作
enum ChildItemMatchAction {
  /// 本地该结构下无同名项 -> 直接新增挂载
  createNew,

  /// 本地该结构下已有同名项且内容完全一致 -> 幂等跳过
  identicalSkip,

  /// 本地该结构下已有同名项但内容存在差异 -> 在当前子层新建副本（如“卫宁方案 (副本)”）
  forkChildCopy,

  /// 用户主动选择：覆盖更新本地同名子项
  overwriteLocalChild,

  /// 跳过该子项
  skip,
}

/// 单个键入方案的匹配决议项
class TypingProfilePlanItem {
  final TypingProfile incoming;
  final TypingProfile? existingLocal;
  ChildItemMatchAction action;

  TypingProfilePlanItem({
    required this.incoming,
    this.existingLocal,
    required this.action,
  });
}

/// 单个内容模板的匹配决议项
class ContentTemplatePlanItem {
  final ContentTemplate incoming;
  final ContentTemplate? existingLocal;
  ChildItemMatchAction action;

  ContentTemplatePlanItem({
    required this.incoming,
    this.existingLocal,
    required this.action,
  });
}

/// 单个结构模板家族单元的完整三层导入计划
class StructureUnitImportPlan {
  final StructureGroundedUnit unit;

  /// 本地匹配到的候选同名/同ID结构模板（若有）
  final Template? matchedLocalStructure;

  /// 本地结构与导入结构的字段列表签名是否完全一致
  final bool slotsSignatureMatched;

  /// 字段差异摘要说明（当 slotsSignatureMatched == false 时提供给 UI 展示）
  final String? slotDiffSummary;

  /// 第一层决议动作
  StructureMatchAction structureAction;

  /// 第二层分支 A：解析流程决议动作
  PipelineMatchAction pipelineAction;

  /// 第二层分支 B：各键入方案决议
  final List<TypingProfilePlanItem> typingProfilePlans;

  /// 第二层分支 C：各内容模板决议
  final List<ContentTemplatePlanItem> contentTemplatePlans;

  StructureUnitImportPlan({
    required this.unit,
    this.matchedLocalStructure,
    required this.slotsSignatureMatched,
    this.slotDiffSummary,
    required this.structureAction,
    required this.pipelineAction,
    required this.typingProfilePlans,
    required this.contentTemplatePlans,
  });
}

/// 独立标准词条库模块的导入计划摘要
class DiagnosisImportPlan {
  final List<FavoriteDiagnosis> newDiagnoses;
  final List<FavoriteDiagnosis> mergedTagDiagnoses;
  final int identicalSkippedCount;
  final List<String> newTags;
  final List<String> newProcedureTags;
  final Map<String, List<String>> newTagsByCatalog;
  bool enabled;

  DiagnosisImportPlan({
    this.newDiagnoses = const [],
    this.mergedTagDiagnoses = const [],
    this.identicalSkippedCount = 0,
    this.newTags = const [],
    this.newProcedureTags = const [],
    this.newTagsByCatalog = const {},
    this.enabled = true,
  });

  int get newDiagnosisCount =>
      newDiagnoses.where((d) => d.catalogType != 'procedure').length;
  int get newProcedureCount =>
      newDiagnoses.where((d) => d.catalogType == 'procedure').length;
  int get mergedDiagnosisCount =>
      mergedTagDiagnoses.where((d) => d.catalogType != 'procedure').length;
  int get mergedProcedureCount =>
      mergedTagDiagnoses.where((d) => d.catalogType == 'procedure').length;

  int get totalIncoming =>
      newDiagnoses.length + mergedTagDiagnoses.length + identicalSkippedCount;

  bool get hasAny =>
      totalIncoming > 0 ||
      newTags.isNotEmpty ||
      newProcedureTags.isNotEmpty ||
      newTagsByCatalog.values.any((tags) => tags.isNotEmpty);
}

/// 引擎 C 完整预检分析与执行计划（Import Plan）
class EngineCImportPlan {
  final EngineCBundleEnvelope envelope;
  final List<StructureUnitImportPlan> unitPlans;
  final DiagnosisImportPlan diagnosisPlan;

  bool importApiConfigs;
  bool importPromptConfigs;
  bool importDeviceConfigs;

  EngineCImportPlan({
    required this.envelope,
    required this.unitPlans,
    required this.diagnosisPlan,
    this.importApiConfigs = false,
    this.importPromptConfigs = false,
    this.importDeviceConfigs = false,
  });

  bool get hasAnyExecutable =>
      unitPlans.any((u) => u.structureAction != StructureMatchAction.skip) ||
      (diagnosisPlan.enabled && diagnosisPlan.hasAny) ||
      importApiConfigs ||
      importPromptConfigs ||
      importDeviceConfigs;

  String? get apiConfigsSummary {
    if (envelope.apiConfigs == null) return null;
    final apis = envelope.apiConfigs!;
    final items = <String>[];
    if (apis['llm'] is Map) {
      final llm = apis['llm'] as Map;
      final count = _extractProvidersCount(llm);
      final active = llm['activeProviderId']?.toString();
      items.add('大模型 ${count > 0 ? "$count 家" : ""}${active != null && active.isNotEmpty ? "(当前 $active)" : ""}');
    }
    if (apis['asr'] is Map) {
      final asr = apis['asr'] as Map;
      final count = _extractProvidersCount(asr);
      items.add('语音识别 ${count > 0 ? "$count 家" : ""}');
    }
    if (apis['ocr'] is Map) {
      final ocr = apis['ocr'] as Map;
      final count = _extractProvidersCount(ocr);
      items.add('文档识图 ${count > 0 ? "$count 家" : ""}');
    }
    return items.isEmpty ? null : items.join(' · ');
  }

  static int _extractProvidersCount(Map map) {
    if (map['providers'] is List) return (map['providers'] as List).length;
    final raw = map['providersMatrix'];
    if (raw is List) return raw.length;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.length;
      } catch (_) {}
    }
    return map['apiKey'] != null && map['apiKey'].toString().trim().isNotEmpty ? 1 : 0;
  }
}

/// 引擎 C 导入执行结果统计
class EngineCImportExecutionResult {
  int createdStructures = 0;
  int reusedStructures = 0;
  int forkedStructures = 0;
  int overwrittenStructures = 0;

  int appliedPipelines = 0;

  int addedTypingProfiles = 0;
  int forkedTypingProfiles = 0;
  int overwrittenTypingProfiles = 0;
  int skippedIdenticalProfiles = 0;

  int addedContentTemplates = 0;
  int forkedContentTemplates = 0;
  int overwrittenContentTemplates = 0;
  int skippedIdenticalContentTemplates = 0;

  int addedDiagnoses = 0;
  int mergedDiagnoses = 0;
  int addedDiagnosisTags = 0;

  int addedProcedures = 0;
  int mergedProcedures = 0;
  int addedProcedureTags = 0;

  // Generic counters across all catalogs.
  int addedCatalogEntries = 0;
  int mergedCatalogEntries = 0;
  int addedCatalogTags = 0;

  int importedLlmProviders = 0;
  int importedAsrProviders = 0;
  int importedOcrProviders = 0;

  bool importedApiConfigs = false;
  bool importedPromptConfigs = false;
  bool importedDeviceConfigs = false;

  final List<String> warnings = [];

  bool get isSuccess => warnings.isEmpty;

  String get summaryText {
    final parts = <String>[];
    if (createdStructures > 0) parts.add('新建文书类型 $createdStructures 个');
    if (reusedStructures > 0) parts.add('匹配复用文书类型 $reusedStructures 个');
    if (forkedStructures > 0) parts.add('新建结构副本 $forkedStructures 个');
    if (overwrittenStructures > 0) parts.add('覆盖文书类型 $overwrittenStructures 个');

    if (appliedPipelines > 0) parts.add('更新解析流程 $appliedPipelines 处');

    final totalProfiles =
        addedTypingProfiles + forkedTypingProfiles + overwrittenTypingProfiles;
    if (totalProfiles > 0) {
      parts.add(
          '键入方案 $totalProfiles 套${forkedTypingProfiles > 0 ? ' (含 $forkedTypingProfiles 套副本)' : ''}');
    }

    final totalCts = addedContentTemplates +
        forkedContentTemplates +
        overwrittenContentTemplates;
    if (totalCts > 0) {
      parts.add(
          '内容模板 $totalCts 个${forkedContentTemplates > 0 ? ' (含 $forkedContentTemplates 个副本)' : ''}');
    }

    if (addedCatalogEntries > 0 || mergedCatalogEntries > 0) {
      parts.add(
          '标准词条库新增 $addedCatalogEntries 条 / 合并 $mergedCatalogEntries 条');
    }
    if (addedCatalogTags > 0) {
      parts.add('新增词库标签 $addedCatalogTags 个');
    }
    if (importedApiConfigs) {
      final aiParts = <String>[];
      if (importedLlmProviders > 0) aiParts.add('大模型 $importedLlmProviders 家');
      if (importedAsrProviders > 0) aiParts.add('语音 $importedAsrProviders 家');
      if (importedOcrProviders > 0) aiParts.add('识图 $importedOcrProviders 家');
      if (aiParts.isNotEmpty) {
        parts.add('AI 服务商与密钥 (${aiParts.join('、')})');
      } else {
        parts.add('API 密钥配置');
      }
    }
    if (importedPromptConfigs) parts.add('Prompt 提示词配置');
    if (importedDeviceConfigs) parts.add('外设与二维码配置');

    if (parts.isEmpty) {
      if (skippedIdenticalProfiles > 0 ||
          skippedIdenticalContentTemplates > 0) {
        return '所有条目与本地完全一致，无需重复创建';
      }
      return '未执行任何变更';
    }
    return '成功处理：${parts.join('，')}';
  }
}
