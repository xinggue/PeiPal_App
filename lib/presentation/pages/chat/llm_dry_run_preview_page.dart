import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/generation/pipeline_executor.dart';

class LlmDryRunPreviewPage extends StatelessWidget {
  final String templateName;
  final List<DryRunStageItem> stages;

  const LlmDryRunPreviewPage({
    super.key,
    required this.templateName,
    required this.stages,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Prompt 监视 · $templateName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: '复制所有阶段 Prompt',
            onPressed: () {
              final b = StringBuffer();
              for (final s in stages) {
                b.writeln('========================================');
                b.writeln('【阶段 ${s.stageIndex}/${s.totalStages}: ${s.stageTitle}】');
                b.writeln('目标字段: ${s.targetSlots.map((sl) => "${sl.label}(${sl.key})").join(", ")}');
                b.writeln('---------------- SYSTEM PROMPT ----------------');
                b.writeln(s.systemPrompt);
                b.writeln('---------------- USER PROMPT ----------------');
                b.writeln(s.userPrompt);
                b.writeln();
              }
              Clipboard.setData(ClipboardData(text: b.toString()));
              showAppToast(context, '已复制所有阶段的 Prompt 到剪贴板');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.amber.withValues(alpha: 0.15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bug_report_outlined,
                    size: 18, color: Colors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前处于 LLM 提示词监视模式 (Dry Run)。未发起任何真实 API 请求，不消耗 Token。\n共规划了 ${stages.length} 个执行阶段，System 与 User 提示词上下排列，前序阶段输出以占位符模拟。',
                    style: TextStyle(
                        fontSize: 12, color: Colors.brown[900], height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          // Stages List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: stages.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = stages[index];
                return _StagePromptCard(item: item);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StagePromptCard extends StatelessWidget {
  final DryRunStageItem item;
  const _StagePromptCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stage Header
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    '${item.stageIndex}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.stageTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '本阶段生成: ${item.targetSlots.map((s) => s.label).join(", ")}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // 1. System Prompt Block
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SYSTEM PROMPT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${item.systemPrompt.length} 字符',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制 System Prompt',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.systemPrompt));
                    showAppToast(context, '已复制阶段 ${item.stageIndex} 的 System Prompt');
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.indigo.withValues(alpha: 0.2),
                ),
              ),
              child: SelectableText(
                item.systemPrompt,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. User Prompt Block
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'USER PROMPT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${item.userPrompt.length} 字符',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制 User Prompt',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.userPrompt));
                    showAppToast(context, '已复制阶段 ${item.stageIndex} 的 User Prompt');
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.teal.withValues(alpha: 0.2),
                ),
              ),
              child: SelectableText(
                item.userPrompt,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
