import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/services/task/task_center.dart';
import '../chat/generation_run_page.dart';

class TaskCenterPage extends ConsumerStatefulWidget {
  const TaskCenterPage({super.key});

  @override
  ConsumerState<TaskCenterPage> createState() => _TaskCenterPageState();
}

class _TaskCenterPageState extends ConsumerState<TaskCenterPage> {
  static final _dateFormat = DateFormat('MM-dd HH:mm:ss');
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 运行中有任务时，以 500ms 频率心跳刷新计时器
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final hasActive = ref.read(taskCenterProvider).activeTasks.isNotEmpty;
      if (hasActive && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taskCenter = ref.watch(taskCenterProvider);
    final tasks = taskCenter.allTasks;
    final activeCount = taskCenter.activeTasks.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('后台任务中心'),
        actions: [
          if (tasks.any((t) => t.isDone))
            TextButton(
              onPressed: () => taskCenter.clearFinishedTasks(),
              child: const Text('清空已完成'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_turned_in_outlined,
                      size: 64, color: Colors.grey.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  const Text('暂无长耗时后台任务',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                  const SizedBox(height: 4),
                  const Text('文书生成、语音转写、图片OCR均在此并发管理',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          : Column(
              children: [
                // Top Status Banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: activeCount > 0
                      ? Colors.blue.withValues(alpha: 0.08)
                      : Colors.grey.withValues(alpha: 0.08),
                  child: Row(
                    children: [
                      Icon(
                        activeCount > 0
                            ? Icons.sync_rounded
                            : Icons.check_circle_outline,
                        size: 18,
                        color: activeCount > 0 ? Colors.blue : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        activeCount > 0
                            ? '当前有 $activeCount 个任务正在运行'
                            : '全部任务已完成',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: activeCount > 0 ? Colors.blue[900] : Colors.green[900],
                        ),
                      ),
                    ],
                  ),
                ),

                // Tasks List
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: tasks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _buildTaskCard(context, ref, taskCenter, task);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    WidgetRef ref,
    TaskCenter taskCenter,
    BackgroundTask task,
  ) {
    Color typeColor;
    String typeLabel;
    IconData typeIcon;

    switch (task.type) {
      case TaskType.generation:
        typeColor = Colors.teal;
        typeLabel = '文书生成';
        typeIcon = Icons.auto_awesome;
        break;
      case TaskType.asr:
        typeColor = Colors.blue;
        typeLabel = '语音识别';
        typeIcon = Icons.mic_none;
        break;
      case TaskType.ocr:
        typeColor = Colors.deepOrange;
        typeLabel = '材料识别';
        typeIcon = Icons.document_scanner_outlined;
        break;
    }

    Color statusColor;
    String statusLabel;
    switch (task.status) {
      case TaskStatus.running:
        statusColor = Colors.blue;
        statusLabel = '执行中';
        break;
      case TaskStatus.success:
        statusColor = Colors.green;
        statusLabel = '已完成';
        break;
      case TaskStatus.failed:
        statusColor = Colors.red;
        statusLabel = '失败';
        break;
      case TaskStatus.cancelled:
        statusColor = Colors.grey;
        statusLabel = '已取消';
        break;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: task.isRunning
              ? Colors.blue.withValues(alpha: 0.4)
              : Colors.grey.withValues(alpha: 0.2),
          width: task.isRunning ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // 如果是生成任务，点击卡片直接切入全屏生成监控界面
          if (task.type == TaskType.generation && task.generationPlan != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GenerationRunPage(
                  plan: task.generationPlan!,
                  patientId: task.patientId,
                  existingTaskId: task.id,
                ),
              ),
            );
          } else if (task.status == TaskStatus.success &&
              task.resultMessageId != null) {
            if (task.type == TaskType.generation) {
              context.push(
                  '/patients/${task.patientId}/records/${task.resultMessageId}/review');
            } else {
              context.push(
                Uri(
                  path: '/patients/${task.patientId}/chat',
                  queryParameters: {'highlightId': task.resultMessageId},
                ).toString(),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcon, size: 12, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: typeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '会话: ${task.patientName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              Text(
                task.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),

              // Stage / Progress description
              Row(
                children: [
                  if (task.isRunning) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      task.stageDescription,
                      style: TextStyle(
                        fontSize: 12,
                        color: task.status == TaskStatus.failed
                            ? Colors.red
                            : Colors.blueGrey,
                      ),
                    ),
                  ),
                ],
              ),

              if (task.isRunning) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],

              // Streaming text preview (if generation task has active text stream)
              if (task.isRunning)
                ValueListenableBuilder<String>(
                  valueListenable: task.streamNotifier,
                  builder: (context, streamText, _) {
                    if (streamText.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          streamText.length > 80
                              ? '...${streamText.substring(streamText.length - 80)}'
                              : streamText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 8),
              // Footer info & actions
              Row(
                children: [
                  Text(
                    '${_dateFormat.format(task.createdAt)} · 耗时 ${(task.effectiveDurationMs / 1000).toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 11,
                      color: task.isRunning ? Colors.blue.shade700 : Colors.grey,
                      fontWeight: task.isRunning ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  if (task.isRunning)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => taskCenter.cancelTask(task.id),
                      child: const Text('取消'),
                    )
                  else if (task.status == TaskStatus.success &&
                      task.resultMessageId != null)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () {
                        if (task.type == TaskType.generation) {
                          context.push(
                              '/patients/${task.patientId}/records/${task.resultMessageId}/review');
                        } else {
                          context.push(
                            Uri(
                              path: '/patients/${task.patientId}/chat',
                              queryParameters: {'highlightId': task.resultMessageId},
                            ).toString(),
                          );
                        }
                      },
                      child: Text(task.type == TaskType.generation ? '审阅文书' : '查看消息'),
                    )
                  else if (task.status == TaskStatus.failed && task.type == TaskType.generation && task.generationPlan != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重试'),
                      onPressed: () {
                        // 启动新任务并直接跳转至运行页
                        final newTaskId = taskCenter.startGenerationTask(
                          plan: task.generationPlan!,
                          patientId: task.patientId,
                          patientName: task.patientName,
                          resumeFrom: task.generationResult,
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GenerationRunPage(
                              plan: task.generationPlan!,
                              patientId: task.patientId,
                              existingTaskId: newTaskId,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
