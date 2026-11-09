import 'package:dio/dio.dart';

import '../../domain/generation/generation_plan.dart';
import '../../domain/models/catalog_definition.dart';
import '../../domain/generation/generation_result.dart';
import '../../domain/generation/standard_catalog.dart';
import '../../domain/models/content_template.dart';
import '../../domain/models/favorite_diagnosis.dart';
import '../../domain/models/message.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/template.dart';
import 'api/api_service.dart';
import 'api/llm_prompt_config.dart';
import 'generation/pipeline_executor.dart';

/// Generation Engine A (domain-agnostic).
/// Fully decoupled: accepts structured-document inputs via [GenerationPlan],
/// executes sequential topological pipeline batches via [PipelineExecutor],
/// and produces a verified, sanitized [GenerationResult].
/// Medical records are the built-in preset, but templates/catalogs can target
/// any structured document workflow.
class GenerationEngine {
  final PipelineExecutor _executor;

  GenerationEngine(
    ApiService api, {
    Future<void> Function(Duration)? sleepOverride,
  }) : _executor = PipelineExecutor(api, sleepOverride: sleepOverride);

  /// 预规划阶段列表（供 UI 提前画出阶段列表、计算总批次数）。
  List<BatchStepPlan> planStages(GenerationPlan plan) =>
      _executor.planBatches(plan);

  /// Executes generation using a structured [GenerationPlan].
  Future<GenerationResult> executePlan(
    GenerationPlan plan, {
    GenerationResult? resumeFrom,
    CancelToken? cancelToken,
    void Function(StageProgressEvent event)? onEvent,
    void Function(String stageTitle, int current, int total)? onProgress,
    void Function(int stageIndex, String chunk, String accumulated)? onStreamChunk,
  }) =>
      _executor.execute(
        plan: plan,
        resumeFrom: resumeFrom,
        cancelToken: cancelToken,
        onEvent: onEvent,
        onProgress: onProgress,
        onStreamChunk: onStreamChunk,
      );

  /// Performs dry-run prompt compilation for all stages without calling LLM.
  List<DryRunStageItem> dryRun(GenerationPlan plan) =>
      _executor.dryRun(plan);

  /// Helper to package inputs into a [GenerationPlan].
  ///
  /// 保证：输入消息无论以何种顺序传入，内部一律先按 [createdAt] 升序排序，
  /// 彻底根除因倒序导致 prompt 倒置与增量截取错误。
  GenerationPlan buildPlan({
    required Template template,
    required ContentTemplate? contentTemplate,
    required Patient patient,
    required List<Message> chatMessages,
    Map<String, List<CatalogItem>> catalogEntriesByType = const {},
    Map<String, CatalogDefinition> catalogs = const {},
    List<FavoriteDiagnosis>? favoriteDiagnoses,
    LlmPromptConfig? promptConfig,
    bool allMaterials = true,
    Set<String>? selectedSlotKeys,
    String? extraInstructions,
    DateTime? now,
  }) {
    // 强制按时间正序排序
    final sortedMessages = List<Message>.from(chatMessages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final historicalRecords = sortedMessages
        .where((m) =>
            m.type == MessageType.generatedRecord &&
            m.recordJson != null &&
            m.recordJson!.trim().isNotEmpty)
        .toList();

    List<Message> rawStream;
    if (allMaterials) {
      rawStream = sortedMessages
          .where((m) => m.type != MessageType.generatedRecord)
          .toList();
    } else {
      final lastRecordIdx = sortedMessages
          .lastIndexWhere((m) => m.type == MessageType.generatedRecord);
      if (lastRecordIdx >= 0) {
        // 自最后一条病历之后产生的材料
        rawStream = sortedMessages
            .sublist(lastRecordIdx + 1)
            .where((m) => m.type != MessageType.generatedRecord)
            .toList();
      } else {
        // 从未生成过历史病历，等同于全量
        rawStream = sortedMessages
            .where((m) => m.type != MessageType.generatedRecord)
            .toList();
      }
    }

    // Merge catalogs map. Entries are grouped by their own catalog type so a
    // surgery slot never receives diagnosis terms (and the reverse).
    final finalCatalogs =
        Map<String, List<CatalogItem>>.from(catalogEntriesByType);
    if (favoriteDiagnoses != null && favoriteDiagnoses.isNotEmpty) {
      for (final d in favoriteDiagnoses) {
        final type = d.catalogType.trim().isEmpty ? 'diagnosis' : d.catalogType;
        finalCatalogs.putIfAbsent(type, () => []).add(
              CatalogItem.fromFavoriteDiagnosis(d),
            );
      }
    }

    return GenerationPlan(
      template: template,
      contentTemplate: contentTemplate,
      patient: patient,
      rawChatStream: rawStream,
      historicalRecords: historicalRecords,
      catalogEntriesByType: finalCatalogs,
      catalogs: catalogs,
      promptConfig: promptConfig ?? const LlmPromptConfig(),
      allMaterials: allMaterials,
      selectedSlotKeys: selectedSlotKeys,
      extraInstructions: extraInstructions,
      now: now,
    );
  }
}
