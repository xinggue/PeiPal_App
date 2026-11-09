import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/generation/generation_log.dart';
import '../../../domain/generation/generation_plan.dart';
import '../../../domain/generation/generation_result.dart';
import '../../../domain/generation/record_validator.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/record_meta.dart';
import '../generation/output_sanitizer.dart';
import '../generation/pipeline_executor.dart';
import '../generation/stage_prompt_compiler.dart';
import '../../../providers/providers.dart';

const _uuid = Uuid();

enum TaskType {
  generation,
  asr,
  ocr,
}

enum TaskStatus {
  running,
  success,
  failed,
  cancelled,
}

class BackgroundTask {
  final String id;
  final TaskType type;
  final String patientId;
  final String patientName;
  final String title;
  TaskStatus status;
  double progress; // 0.0 ~ 1.0
  String stageDescription;
  int currentStageIndex; // 当前正在运行的阶段索引（从 1 开始，0 表示未开始）
  int completedStagesCount; // 已经完成成功的阶段数量
  String currentStreamText;

  /// 高频流式输出通知器：每个 SSE 分片直接更新，供 UI 按帧重建，
  /// 与低频的 [TaskCenter.notifyListeners]（阶段/进度）解耦。
  final ValueNotifier<String> streamNotifier = ValueNotifier<String>('');
  String? resultMessageId;
  String? error;
  DateTime createdAt;
  int durationMs;

  final CancelToken cancelToken;
  GenerationResult? generationResult;
  GenerationPlan? generationPlan;
  bool isManual;
  String? manualPrompt;

  BackgroundTask({
    required this.id,
    required this.type,
    required this.patientId,
    required this.patientName,
    required this.title,
    this.status = TaskStatus.running,
    this.progress = 0.0,
    this.stageDescription = '正在初始化...',
    this.currentStageIndex = 0,
    this.completedStagesCount = 0,
    this.currentStreamText = '',
    this.resultMessageId,
    this.error,
    DateTime? createdAt,
    this.durationMs = 0,
    CancelToken? cancelToken,
    this.generationResult,
    this.generationPlan,
    this.isManual = false,
    this.manualPrompt,
  })  : createdAt = createdAt ?? DateTime.now(),
        cancelToken = cancelToken ?? CancelToken();

  bool get isRunning => status == TaskStatus.running;
  bool get isDone => !isRunning;

  /// 计算当前实际耗时（运行中则动态计算从创建至今的毫秒数，已结束则取固定 durationMs）
  int get effectiveDurationMs {
    if (isRunning) {
      return DateTime.now().difference(createdAt).inMilliseconds;
    }
    return durationMs > 0
        ? durationMs
        : DateTime.now().difference(createdAt).inMilliseconds;
  }

  BackgroundTask copyWith({
    TaskStatus? status,
    double? progress,
    String? stageDescription,
    int? currentStageIndex,
    int? completedStagesCount,
    String? currentStreamText,
    String? resultMessageId,
    String? error,
    int? durationMs,
    GenerationResult? generationResult,
    bool? isManual,
    String? manualPrompt,
  }) {
    final t = BackgroundTask(
      id: id,
      type: type,
      patientId: patientId,
      patientName: patientName,
      title: title,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      stageDescription: stageDescription ?? this.stageDescription,
      currentStageIndex: currentStageIndex ?? this.currentStageIndex,
      completedStagesCount: completedStagesCount ?? this.completedStagesCount,
      currentStreamText: currentStreamText ?? this.currentStreamText,
      resultMessageId: resultMessageId ?? this.resultMessageId,
      error: error ?? this.error,
      createdAt: createdAt,
      durationMs: durationMs ?? this.durationMs,
      cancelToken: cancelToken,
      generationResult: generationResult ?? this.generationResult,
      generationPlan: generationPlan,
      isManual: isManual ?? this.isManual,
      manualPrompt: manualPrompt ?? this.manualPrompt,
    );
    return t;
  }
}

/// 全局任务调度中心：负责长耗时任务的后台异步并发、状态广播与原子落库。
class TaskCenter extends ChangeNotifier {
  final Ref _ref;
  final List<BackgroundTask> _tasks = [];

  TaskCenter(this._ref);

  List<BackgroundTask> get allTasks => List.unmodifiable(_tasks);
  List<BackgroundTask> get tasks => List.unmodifiable(_tasks);
  List<BackgroundTask> get activeTasks =>
      _tasks.where((t) => t.isRunning).toList();

  BackgroundTask? getTask(String id) {
    try {
      return _tasks.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 获取某患者正在运行中的生成任务（如果有）
  BackgroundTask? getRunningGenerationForPatient(String patientId) {
    try {
      return _tasks.firstWhere(
        (t) =>
            t.patientId == patientId &&
            t.type == TaskType.generation &&
            t.isRunning,
      );
    } catch (_) {
      return null;
    }
  }

  /// 取消某个任务
  void cancelTask(String id) {
    final task = getTask(id);
    if (task == null || !task.isRunning) return;
    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel('用户在任务中心主动取消');
    }
    task.status = TaskStatus.cancelled;
    task.error = '已取消';
    notifyListeners();
  }

  /// 清除已结束的任务记录
  void clearFinishedTasks() {
    final removed = _tasks.where((t) => !t.isRunning).toList();
    for (final task in removed) {
      task.streamNotifier.dispose();
    }
    _tasks.removeWhere((t) => !t.isRunning);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final task in _tasks) {
      task.streamNotifier.dispose();
    }
    super.dispose();
  }

  /// 注册外部长耗时任务（如 ASR、OCR）
  void registerTask(BackgroundTask task) {
    _tasks.insert(0, task);
    notifyListeners();
  }

  /// 外部任务状态更新后触发通知
  void notifyTaskUpdated() {
    notifyListeners();
  }

  /// 发起后台病历生成任务
  String startGenerationTask({
    required GenerationPlan plan,
    required String patientId,
    required String patientName,
    GenerationResult? resumeFrom,
  }) {
    final taskId = _uuid.v4();
    final task = BackgroundTask(
      id: taskId,
      type: TaskType.generation,
      patientId: patientId,
      patientName: patientName,
      title: '文书生成 · ${plan.template.name}',
      stageDescription: '正在规划流水线批次...',
      generationPlan: plan,
    );

    _tasks.insert(0, task);
    notifyListeners();

    // 在后台异步执行，不阻塞任何前台导航
    _runGenerationInBackground(task, plan, resumeFrom: resumeFrom);

    return taskId;
  }

  /// 发起手动挡病历生成任务（不发真实网络请求，将平铺拼接好的 Prompt 交由用户复制发给外部 AI）
  String startManualGenerationTask({
    required GenerationPlan plan,
    required String patientId,
    required String patientName,
  }) {
    final taskId = _uuid.v4();
    final flatPrompt = StagePromptCompiler.compileFlatManualPrompt(plan);

    final task = BackgroundTask(
      id: taskId,
      type: TaskType.generation,
      patientId: patientId,
      patientName: patientName,
      title: '手动模式 · ${plan.template.name}',
      stageDescription: '等待贴回外部 AI 回复',
      generationPlan: plan,
      isManual: true,
      manualPrompt: flatPrompt,
    );

    _tasks.insert(0, task);
    notifyListeners();

    return taskId;
  }

  /// 提交并解析手动模式贴回的原始回答文本，存库为病历
  Future<String?> submitManualGenerationResult(
    String taskId,
    String rawResponse,
  ) async {
    final task = getTask(taskId);
    if (task == null || task.generationPlan == null) return null;
    final plan = task.generationPlan!;

    final effectiveSlotList = plan.selectedSlotKeys != null
        ? plan.template.sortedSlots
            .where((s) => plan.selectedSlotKeys!.contains(s.key))
            .toList()
        : plan.template.sortedSlots;

    try {
      task.stageDescription = '正在解析贴回的文书数据...';
      notifyListeners();

      final sanitizedValues = OutputSanitizer.sanitize(
        rawResponse: rawResponse,
        batchSlots: effectiveSlotList,
      );

      final issues = RecordValidator.validateAll(
        slots: effectiveSlotList,
        values: sanitizedValues,
      );

      final genResult = GenerationResult(
        isSuccess: true,
        fieldValues: sanitizedValues,
        stageLogs: [
          StageLog(
            index: 1,
            title: '手动模式生成',
            slotKeys: effectiveSlotList.map((s) => s.key).toList(),
            systemPrompt: '【手动模式】由用户复制对话内容至外部大模型生成',
            userPrompt: task.manualPrompt ?? '',
            rawResponse: rawResponse,
            attempts: 1,
            duration: Duration(milliseconds: task.effectiveDurationMs),
            success: true,
          ),
        ],
        issues: issues,
        duration: Duration(milliseconds: task.effectiveDurationMs),
      );

      task.generationResult = genResult;
      task.progress = 1.0;
      task.stageDescription = '解析成功，正在入库...';
      notifyListeners();

      final msgId = await _persistRecord(
        plan,
        genResult,
        isPartial: false,
        modelOverride: '手动模式 (外部AI)',
      );
      task.resultMessageId = msgId;
      task.status = TaskStatus.success;
      task.stageDescription = '已完成手动模式生成并入库';
      notifyListeners();

      return msgId;
    } catch (e) {
      task.error = '解析失败: $e';
      task.stageDescription = '解析贴回答案失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _runGenerationInBackground(
    BackgroundTask task,
    GenerationPlan plan, {
    GenerationResult? resumeFrom,
  }) async {
    final engine = _ref.read(generationEngineProvider);
    final stopwatch = Stopwatch()..start();

    try {
      final result = await engine.executePlan(
        plan,
        resumeFrom: resumeFrom,
        cancelToken: task.cancelToken,
        onEvent: (event) {
          final frac = event.totalStages > 0
              ? (event.stageIndex - 1) / event.totalStages
              : 0.0;
          task.progress = frac.clamp(0.0, 1.0);
          task.currentStageIndex = event.stageIndex;

          if (event.status == StageExecutionStatus.running) {
            // 新阶段开始，清空上一阶段的流式残影
            task.currentStreamText = '';
            task.streamNotifier.value = '';
          }

          if (event.status == StageExecutionStatus.success) {
            task.completedStagesCount = event.stageIndex;
          }

          task.stageDescription =
              '阶段 ${event.stageIndex}/${event.totalStages} · ${event.stageTitle}';
          if (event.status == StageExecutionStatus.retrying) {
            task.stageDescription += ' (${event.message ?? "重试中"})';
          }
          notifyListeners();
        },
        // 每个分片都直接推给高频通知器，由 UI 按帧合并重建；不再节流，也不整页刷新。
        onStreamChunk: (stageIndex, chunk, accumulated) {
          task.currentStageIndex = stageIndex;
          task.currentStreamText = accumulated;
          task.streamNotifier.value = accumulated;
        },
      );

      stopwatch.stop();
      task.durationMs = stopwatch.elapsedMilliseconds;
      task.generationResult = result;

      if (task.cancelToken.isCancelled) {
        task.status = TaskStatus.cancelled;
        task.error = '已取消';
        notifyListeners();
        return;
      }

      if (result.isSuccess) {
        task.progress = 1.0;
        task.stageDescription = '生成完成，正在写入文书...';
        notifyListeners();

        // 自动原子持久化入库
        final msgId = await _persistRecord(plan, result, isPartial: false);
        task.resultMessageId = msgId;
        task.status = TaskStatus.success;
        task.stageDescription = '已生成并妥善入库';
      } else {
        task.status = TaskStatus.failed;
        task.error = result.errorMessage ?? '生成失败';
        task.stageDescription = '阶段中断: ${result.errorMessage ?? ""}';
      }
    } catch (e) {
      stopwatch.stop();
      task.durationMs = stopwatch.elapsedMilliseconds;
      task.status = TaskStatus.failed;
      task.error = e.toString();
      task.stageDescription = '异常退出: $e';
    } finally {
      notifyListeners();
    }
  }

  /// 将生成产出物落库为 Message 与 GenerationLog
  Future<String> _persistRecord(
    GenerationPlan plan,
    GenerationResult result, {
    required bool isPartial,
    String? modelOverride,
  }) async {
    final msgRepo = _ref.read(messageRepositoryProvider);
    final llmCfg = _ref.read(llmConfigProvider);
    final modelName = modelOverride ?? llmCfg.model;

    final allSlotKeys = plan.template.sortedSlots.map((s) => s.key).toSet();
    final generatedKeys = result.fieldValues.keys.toSet();
    final missingKeys = allSlotKeys.difference(generatedKeys).toList();

    // 筛选出本次明确被 AI 填充非空内容，或者在用户指定子集中的有效激活槽位
    final activeKeys = plan.template.sortedSlots
        .where((s) {
          final val = result.fieldValues[s.key];
          final hasVal = val != null && val.trim().isNotEmpty;
          final isSelected = plan.selectedSlotKeys?.contains(s.key) ?? true;
          return hasVal && isSelected;
        })
        .map((s) => s.key)
        .toList();

    final meta = RecordMeta(
      templateName: plan.template.name,
      templateVersion: plan.template.version,
      contentTemplateId: plan.contentTemplate?.id,
      contentTemplateName: plan.contentTemplate?.name,
      model: modelName,
      allMaterials: plan.allMaterials,
      isPartial: isPartial,
      missingSlotKeys: missingKeys,
      generatedAt: plan.now ?? DateTime.now(),
      totalDurationMs: result.duration.inMilliseconds,
      slotSnapshots: RecordMeta.snapshotSlots(plan.template.sortedSlots),
      aiOriginalValues: Map.from(result.fieldValues),
      activeSlotKeys: activeKeys,
    );

    final orderedMap = <String, String>{};
    for (final s in plan.template.sortedSlots) {
      orderedMap[s.key] = result.fieldValues[s.key] ?? s.defaultValue ?? '';
    }

    final message = Message.generatedRecord(
      patientId: plan.patient.id,
      recordJson: _mapToJsonString(orderedMap),
      templateId: plan.template.id,
      recordMeta: meta,
      createdAt: plan.now ?? DateTime.now(),
    );

    final log = GenerationLog(
      id: _uuid.v4(),
      messageId: message.id,
      patientId: plan.patient.id,
      templateId: plan.template.id,
      templateName: plan.template.name,
      model: modelName,
      status: isPartial ? 'partial' : 'success',
      totalDurationMs: result.duration.inMilliseconds,
      stages: result.stageLogs,
      issues: result.issues,
      errorMessage: result.errorMessage,
      createdAt: DateTime.now(),
    );

    await msgRepo.insertGeneratedAtomic(message, log);

    // 触发全局广播刷新
    _ref.invalidate(messagesProvider(plan.patient.id));
    _ref.invalidate(lastMessageProvider(plan.patient.id));
    _ref.invalidate(patientsProvider);

    return message.id;
  }

  /// 供外部保存部分产出结果
  Future<String?> savePartialResult(String taskId) async {
    final task = getTask(taskId);
    if (task == null ||
        task.generationPlan == null ||
        task.generationResult == null) {
      return null;
    }

    // 防止重复入库：如果此任务已经落过库产生过 messageId，直接返回已有 ID
    if (task.resultMessageId != null && task.resultMessageId!.isNotEmpty) {
      return task.resultMessageId!;
    }

    final msgId = await _persistRecord(
      task.generationPlan!,
      task.generationResult!,
      isPartial: true,
    );
    task.resultMessageId = msgId;
    notifyListeners();
    return msgId;
  }

  static String _mapToJsonString(Map<String, String> map) {
    final buffer = StringBuffer('{\n');
    final entries = map.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final keyEscaped = e.key.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');
      final valEscaped = e.value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');
      buffer.write('  "$keyEscaped": "$valEscaped"');
      if (i < entries.length - 1) buffer.write(',');
      buffer.writeln();
    }
    buffer.write('}');
    return buffer.toString();
  }
}

final taskCenterProvider = ChangeNotifierProvider<TaskCenter>((ref) {
  return TaskCenter(ref);
});
