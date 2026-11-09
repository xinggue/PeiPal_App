import '../../data/services/api/llm_prompt_config.dart';
import '../../domain/models/catalog_definition.dart';
import '../../domain/models/content_template.dart';
import '../../domain/models/message.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/template.dart';
import 'standard_catalog.dart';

/// All raw clinical materials and specifications fed into Generation Engine A.
class GenerationPlan {
  final Template template;
  final ContentTemplate? contentTemplate;
  final Patient patient;
  final List<Message> rawChatStream;
  final List<Message> historicalRecords;

  /// External standard catalog entries grouped by catalogType (e.g. 'diagnosis': [...], 'procedure': [...]).
  final Map<String, List<CatalogItem>> catalogEntriesByType;

  /// Catalog metadata keyed by catalog id, used for display names in prompts.
  final Map<String, CatalogDefinition> catalogs;

  final LlmPromptConfig promptConfig;
  final bool allMaterials;

  /// 用户显式指定的生成字段 key 列表（为 null 表示全量生成）。
  /// 若用户定制了字段子集（isCustomSlotSelection == true），则引擎仅执行包含这些槽位的阶段，且不触发其余字段的自动兜底。
  final Set<String>? selectedSlotKeys;

  /// 用户在生成前最后填写的额外指示/特殊要求/补充病史信息（如："突出患者青霉素过敏"、"着重补充腹部触诊"）
  final String? extraInstructions;

  /// 是否显式定制了字段选择（即非全量全选）
  bool get isCustomSlotSelection =>
      selectedSlotKeys != null &&
      selectedSlotKeys!.length < template.slots.length;

  /// 生成基准时间（为测试和重现性提供确定性；不传则使用当前时间）
  final DateTime? now;

  const GenerationPlan({
    required this.template,
    this.contentTemplate,
    required this.patient,
    required this.rawChatStream,
    required this.historicalRecords,
    this.catalogEntriesByType = const {},
    this.catalogs = const {},
    this.promptConfig = const LlmPromptConfig(),
    this.allMaterials = true,
    this.selectedSlotKeys,
    this.extraInstructions,
    this.now,
  });
}
