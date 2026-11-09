import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/task/task_center.dart';
import '../../pages/chat/generation_run_page.dart';
import 'manual_prompt_preview_dialog.dart';

/// 渲染在聊天流中的生成中卡片：
/// 1. 自动生成：点不进去的占位卡片，展示当前阶段进度
/// 2. 手动挡：提供复制完整提示词、贴回答案解析入库的操作面板
class GenerationPendingBubble extends ConsumerStatefulWidget {
  final BackgroundTask task;

  const GenerationPendingBubble({
    super.key,
    required this.task,
  });

  @override
  ConsumerState<GenerationPendingBubble> createState() =>
      _GenerationPendingBubbleState();
}

class _GenerationPendingBubbleState
    extends ConsumerState<GenerationPendingBubble> {
  bool _isSubmitting = false;

  void _viewPromptDialog() {
    final prompt = widget.task.manualPrompt ?? '';
    if (prompt.isEmpty) return;
    showManualPromptPreviewDialog(
      context: context,
      title: '文书对话内容 · ${widget.task.generationPlan?.template.name ?? "文书"}',
      promptText: prompt,
    );
  }

  Future<void> _showPasteSheet() async {
    final textController = TextEditingController();

    // 尝试读取剪贴板初始文本
    try {
      final clip = await Clipboard.getData('text/plain');
      if (clip?.text != null && clip!.text!.trim().isNotEmpty) {
        textController.text = clip.text!.trim();
      }
    } catch (_) {}

    if (!mounted) {
      textController.dispose();
      return;
    }

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.paste_rounded, color: Colors.teal),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '贴回外部 AI 回复',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '支持包含 markdown 代码块或纯 JSON，系统将自动清洗、校验并写入文书。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textController,
                  maxLines: 8,
                  minLines: 4,
                  decoration: InputDecoration(
                    hintText: '在此粘贴外部 AI 输出的 JSON 内容...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: '从剪贴板粘贴',
                      onPressed: () async {
                        final c = await Clipboard.getData('text/plain');
                        if (c?.text != null) {
                          setSheetState(() {
                            textController.text = c!.text!;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(_isSubmitting ? '正在解析入库...' : '解析并保存为文书'),
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          final raw = textController.text.trim();
                          if (raw.isEmpty) {
                            showAppToast(context, '请先粘贴或输入内容');
                            return;
                          }

                          setSheetState(() => _isSubmitting = true);
                          setState(() => _isSubmitting = true);

                                                    final router = GoRouter.of(context);
                          final navigator = Navigator.of(ctx);

                          try {
                            final taskCenter = ref.read(taskCenterProvider);
                            final msgId =
                                await taskCenter.submitManualGenerationResult(
                              widget.task.id,
                              raw,
                            );

                            if (navigator.canPop()) {
                              navigator.pop();
                            }

                            if (mounted) {
                              showAppToast(context, '文书解析成功，已自动保存入库');
                              if (msgId != null) {
                                router.push(
                                  '/patients/${widget.task.patientId}/records/$msgId/review',
                                );
                              }
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              setSheetState(() => _isSubmitting = false);
                            }
                            if (mounted) {
                              showAppToast(context, '解析失败: $e');
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isSubmitting = false);
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        textController.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isManual = widget.task.isManual;
    final templateName =
        widget.task.generationPlan?.template.name ?? '文书';

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isManual
              ? Colors.amber.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isManual
                ? Colors.amber.withValues(alpha: 0.4)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        child: isManual
            ? _buildManualContent(context, templateName)
            : _buildAutoPendingContent(context, templateName),
      ),
    );
  }

  /// 自动生成中的占位卡片：点击可跳转到任务生成详情监控页
  Widget _buildAutoPendingContent(
      BuildContext context, String templateName) {
    final progress = widget.task.progress.clamp(0.0, 1.0);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (widget.task.generationPlan != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GenerationRunPage(
                plan: widget.task.generationPlan!,
                patientId: widget.task.patientId,
                existingTaskId: widget.task.id,
              ),
            ),
          );
        } else {
          context.push('/tasks');
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI 文书生成中 · $templateName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: Colors.teal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.task.currentStageIndex > 0)
                Text(
                  '阶段 ${widget.task.currentStageIndex}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 16, color: Colors.teal),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.task.stageDescription,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (progress > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.teal.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(Colors.teal),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Row(
            children: [
              Expanded(
                child: Text(
                  '点击卡片可查看实时生成监控与流式日志',
                  style: TextStyle(fontSize: 10.5, color: Colors.teal),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 9, color: Colors.teal),
            ],
          ),
        ],
      ),
    );
  }

  /// 手动模式卡片：点击可查看完整对话内容，支持贴回答案
  Widget _buildManualContent(BuildContext context, String templateName) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _viewPromptDialog,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '手动模式',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '等待贴回答案 · $templateName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: '取消任务',
                onPressed: () {
                  ref.read(taskCenterProvider).cancelTask(widget.task.id);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '材料与对话要求已整理完毕。点击卡片可查看完整内容，复制发送给豆包、Deepseek或网页版 AI 后，将回答贴回即可入库。',
            style: TextStyle(fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 14),
                  label: const Text('查看/复制内容', style: TextStyle(fontSize: 11.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _viewPromptDialog,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.paste, size: 14),
                  label: const Text('贴回答案并入库', style: TextStyle(fontSize: 11.5)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _showPasteSheet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
