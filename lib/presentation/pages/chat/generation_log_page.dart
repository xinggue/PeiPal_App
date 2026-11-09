import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../domain/generation/generation_log.dart';
import '../../../domain/generation/generation_result.dart';

class GenerationLogPage extends StatelessWidget {
  final GenerationLog log;

  const GenerationLogPage({super.key, required this.log});

  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生成日志与审计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: '复制整份日志',
            onPressed: () {
              final b = StringBuffer();
              b.writeln('【文书生成审计日志】');
              b.writeln('模板: ${log.templateName} (${log.templateId})');
              b.writeln('状态: ${log.status}');
              b.writeln('模型: ${log.model ?? "默认"}');
              b.writeln('总耗时: ${(log.totalDurationMs / 1000).toStringAsFixed(1)}s');
              b.writeln('时间: ${_dateFormat.format(log.createdAt)}');
              if (log.errorMessage != null) {
                b.writeln('错误信息: ${log.errorMessage}');
              }
              b.writeln();
              for (final s in log.stages) {
                b.writeln('========================================');
                b.writeln('阶段 ${s.index}: ${s.title}');
                b.writeln('负责字段: ${s.slotKeys.join(", ")}');
                b.writeln('耗时: ${(s.duration.inMilliseconds / 1000).toStringAsFixed(1)}s, 尝试: ${s.attempts}次, 结果: ${s.success ? "成功" : "失败"}');
                if (s.error != null) b.writeln('阶段错误: ${s.error}');
                b.writeln('--- SYSTEM PROMPT ---');
                b.writeln(s.systemPrompt);
                b.writeln('--- USER PROMPT ---');
                b.writeln(s.userPrompt);
                b.writeln('--- RAW RESPONSE ---');
                b.writeln(s.rawResponse ?? '(无返回)');
                b.writeln();
              }
              Clipboard.setData(ClipboardData(text: b.toString()));
              showAppToast(context, '已复制完整生成日志到剪贴板');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Summary Banner Card
          Card(
            elevation: 0,
            color: log.status == 'success'
                ? Colors.green.withValues(alpha: 0.08)
                : (log.status == 'partial'
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.08)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: log.status == 'success'
                    ? Colors.green.withValues(alpha: 0.3)
                    : (log.status == 'partial'
                        ? Colors.orange.withValues(alpha: 0.4)
                        : Colors.red.withValues(alpha: 0.3)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        log.status == 'success'
                            ? Icons.check_circle
                            : (log.status == 'partial'
                                ? Icons.warning_amber
                                : Icons.error),
                        color: log.status == 'success'
                            ? Colors.green
                            : (log.status == 'partial'
                                ? Colors.orange
                                : Colors.red),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        log.status == 'success'
                            ? '生成全部成功'
                            : (log.status == 'partial' ? '部分生成 / 中断' : '生成失败'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(log.totalDurationMs / 1000).toStringAsFixed(1)}s',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('模板: ${log.templateName}',
                      style: const TextStyle(fontSize: 12.5)),
                  Text(
                    '模型: ${log.model ?? "默认"} · 时间: ${_dateFormat.format(log.createdAt)}',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                  if (log.errorMessage != null && log.errorMessage!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '失败原因: ${log.errorMessage}',
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Issues Section
          if (log.issues.isNotEmpty) ...[
            _buildSectionHeader('校验问题 (${log.issues.length})'),
            const SizedBox(height: 6),
            ...log.issues.map((i) => _buildIssueTile(i)),
            const SizedBox(height: 14),
          ],

          // Stages Timeline Section
          _buildSectionHeader('执行阶段明细 (${log.stages.length})'),
          const SizedBox(height: 6),
          ...log.stages.map((s) => _buildStageExpansion(s)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.blueGrey,
      ),
    );
  }

  Widget _buildIssueTile(FieldIssue issue) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              issue.message,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
          Text(issue.key,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStageExpansion(StageLog stage) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: (stage.success ? Colors.grey : Colors.red)
              .withValues(alpha: 0.3),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: !stage.success,
        leading: CircleAvatar(
          radius: 12,
          backgroundColor: stage.success
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.red.withValues(alpha: 0.15),
          child: Icon(
            stage.success ? Icons.check : Icons.close,
            size: 14,
            color: stage.success ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          '阶段 ${stage.index} · ${stage.title}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '耗时 ${(stage.duration.inMilliseconds / 1000).toStringAsFixed(1)}s · 尝试 ${stage.attempts} 次 · 字段: ${stage.slotKeys.join(", ")}',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if (stage.error != null && stage.error!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '异常信息: ${stage.error}',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],

          _buildSubSection('SYSTEM PROMPT', stage.systemPrompt, Colors.indigo),
          const SizedBox(height: 10),
          _buildSubSection('USER PROMPT', stage.userPrompt, Colors.teal),
          const SizedBox(height: 10),
          _buildRawResponseSection(stage.rawResponse ?? '(无返回)'),
        ],
      ),
    );
  }

  /// 区分呈现 Thinking 思考过程与最终输出内容
  Widget _buildRawResponseSection(String rawText) {
    final parsed = _splitThinkingAndAnswer(rawText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parsed.thinking != null && parsed.thinking!.isNotEmpty) ...[
          _buildSubSection(
            'THINKING 思考推理过程',
            parsed.thinking!,
            Colors.purple,
            icon: Icons.psychology_outlined,
          ),
          const SizedBox(height: 10),
          _buildSubSection(
            'FINAL ANSWER 最终回答 / JSON',
            parsed.answer,
            Colors.deepOrange,
            icon: Icons.output_outlined,
          ),
        ] else ...[
          _buildSubSection(
            'RAW RESPONSE 原始返回',
            rawText,
            Colors.deepOrange,
          ),
        ],
      ],
    );
  }

  /// 拆解文本中的思考链与最终回答
  static ({String? thinking, String answer}) _splitThinkingAndAnswer(String text) {
    final trimmed = text.trim();

    // 1. 匹配显式的 <think>...</think> 标签
    final thinkTagMatch = RegExp(r'<think>([\s\S]*?)<\/think>', caseSensitive: false).firstMatch(trimmed);
    if (thinkTagMatch != null) {
      final thinkContent = thinkTagMatch.group(1)?.trim();
      final answerContent = trimmed.replaceAll(thinkTagMatch.group(0)!, '').trim();
      return (thinking: thinkContent, answer: answerContent);
    }

    // 2. 匹配以英文/中文前置思考文字 + 尾部 JSON 的情形
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace > 40 && lastBrace > firstBrace) {
      // 在 JSON 出现前有大段思考文字
      final thinkingPrefix = trimmed.substring(0, firstBrace).trim();
      final answerJson = trimmed.substring(firstBrace, lastBrace + 1).trim();
      return (thinking: thinkingPrefix, answer: answerJson);
    }

    return (thinking: null, answer: trimmed);
  }

  Widget _buildSubSection(
    String label,
    String content,
    Color color, {
    IconData? icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 12, color: color),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: color),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text('${content.length} 字符',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Spacer(),
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.copy, size: 14),
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  showAppToast(ctx, '已复制 $label');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}
