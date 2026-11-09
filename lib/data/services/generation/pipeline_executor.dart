import 'dart:async';
import 'package:dio/dio.dart';

import '../../../domain/generation/generation_plan.dart';
import '../../../domain/generation/generation_result.dart';
import '../../../domain/generation/record_validator.dart';
import '../../../domain/models/pipeline_graph.dart';
import '../../../domain/models/template.dart';
import '../api/api_service.dart';
import 'llm_error_mapper.dart';
import 'output_sanitizer.dart';
import 'output_schema_builder.dart';
import 'stage_prompt_compiler.dart';

class BatchStepPlan {
  final String title;
  final List<TemplateSlot> slots;
  final String? customPrompt;

  const BatchStepPlan({
    required this.title,
    required this.slots,
    this.customPrompt,
  });
}

class DryRunStageItem {
  final int stageIndex;
  final int totalStages;
  final String stageTitle;
  final List<TemplateSlot> targetSlots;
  final String systemPrompt;
  final String userPrompt;

  const DryRunStageItem({
    required this.stageIndex,
    required this.totalStages,
    required this.stageTitle,
    required this.targetSlots,
    required this.systemPrompt,
    required this.userPrompt,
  });
}

class _ExecutionUnit {
  final String key;
  int col;
  int row;
  final List<PipelineNode> nodes;
  final int? group;

  _ExecutionUnit({
    required this.key,
    required this.col,
    required this.row,
    required this.nodes,
    this.group,
  });
}

enum StageExecutionStatus {
  pending,
  running,
  retrying,
  success,
  failed,
}

class StageProgressEvent {
  final int stageIndex;
  final int totalStages;
  final String stageTitle;
  final StageExecutionStatus status;
  final int attempt;
  final String? message;

  const StageProgressEvent({
    required this.stageIndex,
    required this.totalStages,
    required this.stageTitle,
    required this.status,
    this.attempt = 1,
    this.message,
  });
}

class PipelineExecutor {
  final ApiService _api;
  final Future<void> Function(Duration)? _sleepOverride;

  PipelineExecutor(
    this._api, {
    this._sleepOverride,
  });

  Future<void> _sleep(Duration d) =>
      _sleepOverride != null ? _sleepOverride(d) : Future.delayed(d);

  /// 根据模板流程图与全量槽位规划批次。
  ///
  /// 保证：
  /// 1. 按图的拓扑序执行；
  /// 2. 跨批次槽位去重（优先由先出现的节点生成）；
  /// 3. 若用户定制了字段选择（plan.isCustomSlotSelection），仅规划并执行包含用户指定槽位的批次，
  ///    并跳过自动兜底步骤（因为用户已有明确的选择意图）；
  /// 4. 默认全选时，未被任何节点覆盖的槽位自动聚拢为末尾一个批次，绝不遗漏；
  /// 5. 流程图为空时，回落为包含目标槽位的单批次。
  List<BatchStepPlan> planBatches(GenerationPlan plan) {
    final graph = plan.template.pipeline;
    final allSortedSlots = plan.template.sortedSlots;

    // 过滤出目标槽位集合（若指定了 selectedSlotKeys 则以此为准）
    final targetSlotKeys = plan.selectedSlotKeys ?? {for (final s in allSortedSlots) s.key};
    final effectiveSlotList =
        allSortedSlots.where((s) => targetSlotKeys.contains(s.key)).toList();
    final allSlotMap = {for (final s in effectiveSlotList) s.key: s};

    final effectiveNodes =
        graph.nodes.where((n) => n.slotKeys.isNotEmpty).toList();

    final batches = <BatchStepPlan>[];
    final assignedSlotKeys = <String>{};

    if (effectiveNodes.isNotEmpty) {
      final nodeById = {for (final n in graph.nodes) n.id: n};
      final unitsMap = <String, _ExecutionUnit>{};

      for (final node in effectiveNodes) {
        final unitKey =
            node.isGrouped ? 'group_${node.group}' : 'node_${node.id}';
        final existing = unitsMap[unitKey];
        if (existing == null) {
          unitsMap[unitKey] = _ExecutionUnit(
            key: unitKey,
            col: node.col,
            row: node.row,
            nodes: [node],
            group: node.isGrouped ? node.group : null,
          );
        } else {
          existing.nodes.add(node);
          if (node.col < existing.col) existing.col = node.col;
          if (node.row < existing.row) existing.row = node.row;
        }
      }

      final inDegree = <String, int>{for (final k in unitsMap.keys) k: 0};
      final adj = <String, Set<String>>{for (final k in unitsMap.keys) k: {}};

      for (final edge in graph.edges) {
        final fNode = nodeById[edge.from];
        final tNode = nodeById[edge.to];
        if (fNode == null || tNode == null) continue;

        final fKey =
            fNode.isGrouped ? 'group_${fNode.group}' : 'node_${fNode.id}';
        final tKey =
            tNode.isGrouped ? 'group_${tNode.group}' : 'node_${tNode.id}';

        if (fKey != tKey &&
            unitsMap.containsKey(fKey) &&
            unitsMap.containsKey(tKey)) {
          if (!adj[fKey]!.contains(tKey)) {
            adj[fKey]!.add(tKey);
            inDegree[tKey] = (inDegree[tKey] ?? 0) + 1;
          }
        }
      }

      final ready = unitsMap.keys.where((k) => inDegree[k] == 0).toList();
      void sortReady() {
        ready.sort((a, b) {
          final uA = unitsMap[a]!;
          final uB = unitsMap[b]!;
          final c = uA.col.compareTo(uB.col);
          return c != 0 ? c : uA.row.compareTo(uB.row);
        });
      }

      sortReady();

      final orderedUnits = <_ExecutionUnit>[];
      while (ready.isNotEmpty) {
        final curKey = ready.removeAt(0);
        orderedUnits.add(unitsMap[curKey]!);

        for (final nxt in adj[curKey] ?? const <String>{}) {
          inDegree[nxt] = (inDegree[nxt] ?? 1) - 1;
          if (inDegree[nxt] == 0) {
            ready.add(nxt);
            sortReady();
          }
        }
      }

      if (orderedUnits.length < unitsMap.length) {
        for (final u in unitsMap.values) {
          if (!orderedUnits.contains(u)) orderedUnits.add(u);
        }
      }

      for (final unit in orderedUnits) {
        final rawKeys = unit.nodes.expand((n) => n.slotKeys).toList();
        final unitSlots = <TemplateSlot>[];
        for (final k in rawKeys) {
          if (!assignedSlotKeys.contains(k) && allSlotMap.containsKey(k)) {
            assignedSlotKeys.add(k);
            unitSlots.add(allSlotMap[k]!);
          }
        }

        if (unitSlots.isEmpty) continue;

        String customPrompt = '';
        String batchTitle = '';

        if (unit.group != null) {
          final groupPrompt = graph.groupPrompts[unit.group] ?? '';
          customPrompt = groupPrompt.isNotEmpty
              ? groupPrompt
              : unit.nodes
                  .map((n) => n.prompt)
                  .where((p) => p.isNotEmpty)
                  .join('\n');
          batchTitle = '分组 (${unit.nodes.map((n) => n.label).join("+")})';
        } else {
          final node = unit.nodes.first;
          customPrompt = node.prompt;
          batchTitle = node.label;
        }

        batches.add(BatchStepPlan(
          title: batchTitle,
          slots: unitSlots,
          customPrompt: customPrompt.isNotEmpty ? customPrompt : null,
        ));
      }
    }

    // 只有在默认全量时才进行自动兜底，用户显式定制了字段时跳过兜底
    if (!plan.isCustomSlotSelection) {
      final unassignedSlots =
          effectiveSlotList.where((s) => !assignedSlotKeys.contains(s.key)).toList();
      if (unassignedSlots.isNotEmpty) {
        batches.add(BatchStepPlan(
          title: batches.isEmpty ? '完整文书生成' : '其余字段',
          slots: unassignedSlots,
        ));
      }
    } else {
      // 若用户定制了字段，但这些字段没有落入任何 DAG 节点，作为唯一批次执行
      if (batches.isEmpty && effectiveSlotList.isNotEmpty) {
        batches.add(BatchStepPlan(
          title: '所选字段生成',
          slots: effectiveSlotList,
        ));
      }
    }

    return batches.isNotEmpty
        ? batches
        : [BatchStepPlan(title: '完整文书生成', slots: effectiveSlotList)];
  }

  /// 纯本地编译各阶段 Prompt（用于监视器）。
  List<DryRunStageItem> dryRun(GenerationPlan plan) {
    final batches = planBatches(plan);
    final accumulated = <String, String>{};
    final items = <DryRunStageItem>[];

    for (int i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final prompt = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: batch.slots,
        accumulatedOutputs: accumulated,
        batchPrompt: batch.customPrompt,
        batchTitle: batch.title,
      );

      items.add(DryRunStageItem(
        stageIndex: i + 1,
        totalStages: batches.length,
        stageTitle: batch.title,
        targetSlots: batch.slots,
        systemPrompt: prompt.systemPrompt,
        userPrompt: prompt.userPrompt,
      ));

      for (final s in batch.slots) {
        accumulated[s.key] = '[待第 ${i + 1} 阶段「${batch.title}」生成]';
      }
    }

    return items;
  }

  /// 顺序执行管线生成。
  ///
  /// 支持：
  /// - [resumeFrom]：断点续跑，继承已成功的阶段与字段值；
  /// - [cancelToken]：支持随时在阶段间或请求中取消；
  /// - [onEvent]：实时汇报阶段状态（开始/重试/成功/失败）；
  /// - 智能重试：格式错误带提示重跑 1 次，网络/5xx/429 错误指数退避重试最多 2 次；
  /// - 严格审计：每个阶段生成 [StageLog]，记录 Prompt 与模型返回。
  Future<GenerationResult> execute({
    required GenerationPlan plan,
    GenerationResult? resumeFrom,
    CancelToken? cancelToken,
    void Function(StageProgressEvent event)? onEvent,
    void Function(String stageTitle, int current, int total)? onProgress,
    void Function(int stageIndex, String chunk, String accumulated)? onStreamChunk,
  }) async {
    final stopwatch = Stopwatch()..start();
    final batches = planBatches(plan);
    final totalStages = batches.length;

    final accumulatedOutputs = <String, String>{};
    final executedBatchTitles = <String>[];
    final stageLogs = <StageLog>[];

    int startStageIndex = 0;
    if (resumeFrom != null && resumeFrom.completedStages > 0) {
      accumulatedOutputs.addAll(resumeFrom.fieldValues);
      executedBatchTitles.addAll(resumeFrom.executedBatches);
      // 仅继承已成功阶段的日志，未成功的阶段将在本次重试中重新记录
      stageLogs.addAll(resumeFrom.stageLogs.take(resumeFrom.completedStages));
      startStageIndex = resumeFrom.completedStages;
    }

    for (int i = startStageIndex; i < totalStages; i++) {
      if (cancelToken?.isCancelled == true) {
        stopwatch.stop();
        return GenerationResult.failure(
          '用户已取消生成',
          duration: stopwatch.elapsed,
          fieldValues: accumulatedOutputs,
          stageLogs: stageLogs,
          executedBatches: executedBatchTitles,
          completedStages: i,
          totalStages: totalStages,
        );
      }

      final batch = batches[i];
      final stageIndex = i + 1;
      onProgress?.call(batch.title, stageIndex, totalStages);

      onEvent?.call(StageProgressEvent(
        stageIndex: stageIndex,
        totalStages: totalStages,
        stageTitle: batch.title,
        status: StageExecutionStatus.running,
      ));

      final compiledPrompt = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: batch.slots,
        accumulatedOutputs: accumulatedOutputs,
        batchPrompt: batch.customPrompt,
        batchTitle: batch.title,
      );

      final jsonSchema = OutputSchemaBuilder.build(
        stageTitle: batch.title,
        slots: batch.slots,
      );

      Map<String, String>? batchResult;
      String? lastRawResponse;
      String? stageError;
      int attempt = 0;
      int formatErrorCount = 0;
      int networkErrorCount = 0;

      final stageStopwatch = Stopwatch()..start();

      while (attempt < 4) {
        if (cancelToken?.isCancelled == true) {
          stageError = '用户取消';
          break;
        }

        attempt++;
        final isFormatRetry = formatErrorCount > 0;
        final userPromptToSend = isFormatRetry
            ? '${compiledPrompt.userPrompt}\n\n[重要提醒：上次返回内容未能成功提取出指定的字段 JSON，请务必只输出严格的纯 JSON 对象，格式为 {"字段key": "值"}]'
            : compiledPrompt.userPrompt;

        try {
          final raw = await _api.chatCompletion(
            systemPrompt: compiledPrompt.systemPrompt,
            userPrompt: userPromptToSend,
            jsonSchema: jsonSchema,
            cancelToken: cancelToken,
            onChunk: (chunk, acc) {
              onStreamChunk?.call(stageIndex, chunk, acc);
            },
          );
          lastRawResponse = raw;

          batchResult = OutputSanitizer.sanitize(
            rawResponse: raw,
            batchSlots: batch.slots,
          );
          break; // 清洗成功！
        } on FormatException catch (e) {
          formatErrorCount++;
          stageError = e.message;
          if (formatErrorCount >= 2) {
            // 格式错误重试 1 次仍不行，停止尝试
            break;
          }
          onEvent?.call(StageProgressEvent(
            stageIndex: stageIndex,
            totalStages: totalStages,
            stageTitle: batch.title,
            status: StageExecutionStatus.retrying,
            attempt: attempt + 1,
            message: '返回格式异常，正在带提示重试...',
          ));
        } catch (e) {
          if (cancelToken?.isCancelled == true) {
            stageError = '用户取消';
            break;
          }

          stageError = LlmErrorMapper.describe(e);
          final transient = LlmErrorMapper.isTransient(e);

          if (!transient || networkErrorCount >= 2) {
            // 非瞬态错误（如 401/404）或网络重试已达 2 次，不再重试
            break;
          }

          networkErrorCount++;
          final backoffSeconds = networkErrorCount * 2;
          onEvent?.call(StageProgressEvent(
            stageIndex: stageIndex,
            totalStages: totalStages,
            stageTitle: batch.title,
            status: StageExecutionStatus.retrying,
            attempt: attempt + 1,
            message: '网络抖动 (${LlmErrorMapper.describe(e)})，${backoffSeconds}s 后自动重试...',
          ));

          await _sleep(Duration(seconds: backoffSeconds));
        }
      }

      stageStopwatch.stop();

      final log = StageLog(
        index: stageIndex,
        title: batch.title,
        slotKeys: batch.slots.map((s) => s.key).toList(),
        systemPrompt: compiledPrompt.systemPrompt,
        userPrompt: compiledPrompt.userPrompt,
        rawResponse: lastRawResponse,
        attempts: attempt,
        duration: stageStopwatch.elapsed,
        success: batchResult != null,
        error: stageError,
      );
      stageLogs.add(log);

      if (batchResult == null) {
        onEvent?.call(StageProgressEvent(
          stageIndex: stageIndex,
          totalStages: totalStages,
          stageTitle: batch.title,
          status: StageExecutionStatus.failed,
          attempt: attempt,
          message: stageError,
        ));

        stopwatch.stop();
        return GenerationResult.failure(
          '第 $stageIndex 阶段「${batch.title}」失败: ${stageError ?? "未知错误"}',
          duration: stopwatch.elapsed,
          fieldValues: accumulatedOutputs,
          stageLogs: stageLogs,
          executedBatches: executedBatchTitles,
          completedStages: i,
          totalStages: totalStages,
        );
      }

      accumulatedOutputs.addAll(batchResult);
      executedBatchTitles.add(batch.title);

      onEvent?.call(StageProgressEvent(
        stageIndex: stageIndex,
        totalStages: totalStages,
        stageTitle: batch.title,
        status: StageExecutionStatus.success,
        attempt: attempt,
      ));
    }

    stopwatch.stop();

    // 校验全部字段，记录告警（如选项不符、必填为空）
    final issues = RecordValidator.validateAll(
      slots: plan.template.sortedSlots,
      values: accumulatedOutputs,
    );

    return GenerationResult(
      isSuccess: true,
      fieldValues: accumulatedOutputs,
      executedBatches: executedBatchTitles,
      stageLogs: stageLogs,
      issues: issues,
      completedStages: totalStages,
      totalStages: totalStages,
      duration: stopwatch.elapsed,
    );
  }
}
