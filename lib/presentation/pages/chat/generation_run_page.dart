import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/generation/pipeline_executor.dart';
import '../../../data/services/task/task_center.dart';
import '../../../domain/generation/generation_log.dart';
import '../../../domain/generation/generation_plan.dart';
import '../../../providers/providers.dart';
import 'generation_log_page.dart';

class GenerationRunPage extends ConsumerStatefulWidget {
  final GenerationPlan plan;
  final String patientId;
  final String? existingTaskId;

  const GenerationRunPage({
    super.key,
    required this.plan,
    required this.patientId,
    this.existingTaskId,
  });

  @override
  ConsumerState<GenerationRunPage> createState() => _GenerationRunPageState();
}

class _GenerationRunPageState extends ConsumerState<GenerationRunPage> {
  late List<BatchStepPlan> _stages;
  late String _taskId;
  Timer? _ticker;
  int _elapsedSeconds = 0;
  bool _hasPopped = false;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(generationEngineProvider);
    _stages = engine.planStages(widget.plan);

    final taskCenter = ref.read(taskCenterProvider);

    if (widget.existingTaskId != null) {
      _taskId = widget.existingTaskId!;
    } else {
      // 在全局任务中心登记并立即异步启动任务
      _taskId = taskCenter.startGenerationTask(
        plan: widget.plan,
        patientId: widget.patientId,
        patientName: widget.plan.patient.name,
      );
    }

    _startTimer();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _onCancel() {
    ref.read(taskCenterProvider).cancelTask(_taskId);
  }

  void _onRetry() {
    if (_isRetrying) return;
    final taskCenter = ref.read(taskCenterProvider);
    final task = taskCenter.getTask(_taskId);
    if (task == null) return;

    setState(() => _isRetrying = true);

    // 重新发起续跑任务并直接将页面绑定为新任务 ID
    final newTaskId = taskCenter.startGenerationTask(
      plan: widget.plan,
      patientId: widget.patientId,
      patientName: widget.plan.patient.name,
      resumeFrom: task.generationResult,
    );

    setState(() {
      _taskId = newTaskId;
      _isRetrying = false;
      _elapsedSeconds = 0;
    });

    showAppToast(context, '已重新启动生成任务');
  }

  Future<void> _onSavePartial() async {
    final taskCenter = ref.read(taskCenterProvider);
    final msgId = await taskCenter.savePartialResult(_taskId);
    if (msgId != null && mounted && !_hasPopped) {
      _hasPopped = true;
      if (Navigator.canPop(context)) {
        Navigator.pop(context, msgId);
      }
    }
  }

  void _onViewLog(BackgroundTask task) {
    final result = task.generationResult;
    if (result == null) return;
    final log = GenerationLog(
      id: 'preview',
      messageId: task.resultMessageId ?? 'preview',
      patientId: widget.patientId,
      templateId: widget.plan.template.id,
      templateName: widget.plan.template.name,
      model: ref.read(llmConfigProvider).model,
      status: result.isSuccess ? 'success' : 'partial',
      totalDurationMs: task.durationMs,
      stages: result.stageLogs,
      issues: result.issues,
      errorMessage: result.errorMessage,
      createdAt: DateTime.now(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GenerationLogPage(log: log)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final taskCenter = ref.watch(taskCenterProvider);
    final task = taskCenter.getTask(_taskId);

    // 任务成功完成时，如果页面仍在前台，自动返回并带回产出的 messageId（防重复 pop 导致黑屏）
    if (task != null && task.status == TaskStatus.success && task.resultMessageId != null && !_hasPopped) {
      _hasPopped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context, task.resultMessageId);
        }
      });
    }

    final isRunning = task?.isRunning ?? false;
    final isFailed = task?.status == TaskStatus.failed;
    final isCancelled = task?.status == TaskStatus.cancelled;

    return PopScope(
      canPop: true, // 允许退出，任务在后台继续
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        if (isRunning) {
          showAppToast(context, '已转入后台运行，可在任务中心查看');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('生成文书 · ${widget.plan.template.name}'),
          actions: [
            if (isRunning)
              TextButton.icon(
                icon: const Icon(Icons.arrow_downward, size: 16),
                label: const Text('后台运行'),
                onPressed: () => Navigator.pop(context),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            // Top Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(
                    isRunning
                        ? Icons.stream_rounded
                        : (task?.status == TaskStatus.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline),
                    color: isRunning
                        ? Colors.blue
                        : (task?.status == TaskStatus.success ? Colors.green : Colors.red),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRunning
                              ? (task?.stageDescription ?? '正在执行...')
                              : (task?.status == TaskStatus.success
                                  ? '生成完毕！正在写入文书...'
                                  : (isCancelled ? '生成已取消' : '生成中断 / 失败')),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                        ),
                        Text(
                          '会话: ${widget.plan.patient.name} · 共 ${_stages.length} 个阶段 · 耗时 ${_elapsedSeconds}s',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (isRunning)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: _onCancel,
                      child: const Text('终止'),
                    ),
                ],
              ),
            ),

            if (isRunning) ...[
              LinearProgressIndicator(
                value: task != null && task.progress > 0 ? task.progress : null,
                minHeight: 3,
              ),
            ],

            // Realtime Stream Text Box (当有模型吐字流时展示实时打字机)
            if (task != null && isRunning)
              ValueListenableBuilder<String>(
                valueListenable: task.streamNotifier,
                builder: (context, streamText, _) {
                  if (streamText.isEmpty) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            const Text('大模型流式输出实时接收中...',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('${streamText.length} 字符',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _StreamingTextView(text: streamText),
                      ],
                    ),
                  );
                },
              ),

            // Stages Timeline List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _stages.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final stage = _stages[index];
                  final stageNumber = index + 1;

                  // 该阶段是否已完成：已经成功跑完的阶段数 >= stageNumber
                  final completedStages = task?.completedStagesCount ??
                      (task?.generationResult?.completedStages ?? 0);
                  final isDone = completedStages >= stageNumber;

                  // 该阶段是否正在运行：当前任务在运行态，且当前阶段刚好是该 stageNumber，且未完成
                  final currentRunningStageIndex = task?.currentStageIndex ?? 1;
                  final isCurrentRunning = isRunning &&
                      !isDone &&
                      currentRunningStageIndex == stageNumber;

                  final isStageFailed = isFailed &&
                      (currentRunningStageIndex == stageNumber);

                  return _buildStageTile(
                    index: stageNumber,
                    title: stage.title,
                    slots: stage.slots,
                    isDone: isDone,
                    isRunning: isCurrentRunning,
                    isFailed: isStageFailed,
                  );
                },
              ),
            ),

            // Bottom Action Bar when Failed / Cancelled
            if (task != null && (isFailed || isCancelled))
              SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isCancelled ? Icons.info_outline : Icons.warning_amber_rounded,
                            color: isCancelled ? Colors.grey : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task.error ?? '执行中断',
                              style: TextStyle(
                                color: isCancelled ? Colors.grey[700] : Colors.red,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (task.generationResult?.stageLogs.isNotEmpty == true)
                            TextButton.icon(
                              icon: const Icon(Icons.receipt_long_outlined, size: 16),
                              label: const Text('查看日志'),
                              onPressed: () => _onViewLog(task),
                            ),
                          const Spacer(),
                          if (task.generationResult?.fieldValues.isNotEmpty == true)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: Text(
                                  '保存已产出的 ${task.generationResult!.fieldValues.length} 项'),
                              onPressed: _onSavePartial,
                            ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            icon: _isRetrying
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 16),
                            label: Text(
                              _isRetrying
                                  ? '启动中...'
                                  : (task.generationResult != null &&
                                          task.generationResult!.completedStages > 0
                                      ? '从第 ${task.generationResult!.completedStages + 1} 阶段继续'
                                      : '重试生成'),
                            ),
                            onPressed: _isRetrying ? null : _onRetry,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageTile({
    required int index,
    required String title,
    required List<dynamic> slots,
    required bool isDone,
    required bool isRunning,
    required bool isFailed,
  }) {
    Widget statusIcon;
    Color borderColor;

    if (isDone) {
      statusIcon = const Icon(Icons.check_circle, color: Colors.green, size: 22);
      borderColor = Colors.green.withValues(alpha: 0.4);
    } else if (isRunning) {
      statusIcon = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
      borderColor = Colors.blue.withValues(alpha: 0.6);
    } else if (isFailed) {
      statusIcon = const Icon(Icons.cancel, color: Colors.red, size: 22);
      borderColor = Colors.red.withValues(alpha: 0.4);
    } else {
      statusIcon = CircleAvatar(
        radius: 11,
        backgroundColor: Colors.grey.withValues(alpha: 0.15),
        child: Text('$index', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      );
      borderColor = Colors.grey.withValues(alpha: 0.2);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRunning
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: isRunning ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              statusIcon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '阶段 $index · $title',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: (!isDone && !isRunning && !isFailed) ? Colors.grey : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '负责字段: ${slots.map((s) => s.label).join(", ")}',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// 高频刷新的实时流文本，末尾带一个呼吸式闪烁光标。
///
/// 独立成 StatefulWidget，保证光标动画在文本高频重建时不会被重置。
class _StreamingTextView extends StatefulWidget {
  final String text;

  const _StreamingTextView({required this.text});

  @override
  State<_StreamingTextView> createState() => _StreamingTextViewState();
}

class _StreamingTextViewState extends State<_StreamingTextView>
    with SingleTickerProviderStateMixin {
  static const int _maxVisibleChars = 3000;

  late final AnimationController _cursorController;
  late final Animation<double> _cursorOpacity;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..repeat(reverse: true);
    _cursorOpacity =
        Tween<double>(begin: 1, end: 0).animate(_cursorController);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.text;
    final truncated = full.length > _maxVisibleChars;
    final visible =
        truncated ? full.substring(full.length - _maxVisibleChars) : full;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 110),
      child: SingleChildScrollView(
        reverse: true,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.4,
              color: Colors.black87,
            ),
            children: [
              if (truncated) const TextSpan(text: '…'),
              TextSpan(text: visible),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: FadeTransition(
                  opacity: _cursorOpacity,
                  child: const Text(
                    '▍',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.4,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
