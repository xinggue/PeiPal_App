import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/typing_done_prefs.dart';
import '../../../providers/providers.dart';
import '../common/app_toast.dart';
import '../common/typing_done_feedback.dart';
import 'ble_connect_manual_sheet.dart';
import 'draggable_typing_overlay.dart';

class TypingTestSample {
  final String label;
  final String description;
  final String text;
  final bool isCustomizable;

  const TypingTestSample({
    required this.label,
    required this.description,
    required this.text,
    this.isCustomizable = false,
  });
}

const kTypingTestSamples = <TypingTestSample>[
  TypingTestSample(
    label: '打开记事本并输入示例文本',
    description: '会打开 Windows 记事本并输入一段中英双语示例文本。',
    text: '{WIN+R}{DELAY:1000}notepad{ENTER}{DELAY:2000}'
        '你现在看到的是来自小培同学 App 发送的测试文本。\n'
        'You are now seeing the test text sent from the DocMaster Pei App.\n'
        '中英双语与数字符号测试：1234567890！@#￥%……&*（）——+【】；‘，。/、\n'
        'The quick brown fox jumps over the lazy dog.\n'
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz',
  ),
  TypingTestSample(
    label: '特殊字符',
    description: '会打出常用特殊符号示例。',
    text: '正负 ±\n'
        '乘号 ×\n'
        '除号 ÷\n'
        '左箭 ←\n'
        '上箭 ↑\n'
        '右箭 →\n'
        '下箭 ↓\n'
        '摄氏 ℃\n'
        '度数 °\n'
        '千分 ‰\n'
        '小等 ≤\n'
        '大等 ≥\n'
        '不等 ≠\n'
        '约等 ≈\n'
        '无穷 ∞\n'
        '根号 √\n'
        '圆一 ①\n'
        '圆二 ②\n'
        '圆三 ③\n'
        '圆四 ④\n'
        '圆五 ⑤\n'
        '圆六 ⑥\n'
        '圆七 ⑦\n'
        '圆八 ⑧\n'
        '圆九 ⑨\n'
        '圆十 ⑩\n'
        '罗马Ⅰ Ⅰ\n'
        '罗马Ⅱ Ⅱ\n'
        '罗马Ⅲ Ⅲ\n'
        '罗马Ⅳ Ⅳ\n'
        '罗马Ⅴ Ⅴ\n'
        '阿尔法 α\n'
        '贝塔 β\n'
        '伽马 γ\n'
        '德尔塔 δ\n'
        '欧米伽 ω\n'
        '微米 μ\n'
        '章节 §\n'
        '编号 №\n'
        '星号 ★\n'
        '方块 ■',
  ),
  TypingTestSample(
    label: '字符画',
    description: '会画出一个爱心字符画。',
    text: '一一爱爱爱一一一爱爱爱一一\n'
        '一爱爱爱爱爱一爱爱爱爱爱一\n'
        '爱爱爱爱爱爱爱爱爱爱爱爱爱\n'
        '爱爱爱爱爱爱爱爱爱爱爱爱爱\n'
        '一爱爱爱爱爱爱爱爱爱爱爱一\n'
        '一一爱爱爱爱爱爱爱爱爱一一\n'
        '一一一爱爱爱爱爱爱爱一一一\n'
        '一一一一爱爱爱爱爱一一一一\n'
        '一一一一一爱爱爱一一一一一\n'
        '一一一一一一爱一一一一一一',
  ),
  TypingTestSample(
    label: '长文本稳定性',
    description: '会循环多行输入相同长度的测试文本。',
    text: '',
    isCustomizable: true,
  ),
];

/// 测试打字组件：提供 4 组专业诊断测试预设，复用完整全局发送管线（悬浮窗、进度跟踪、急停）
class TypingTestPanel extends ConsumerStatefulWidget {
  const TypingTestPanel({super.key});

  @override
  ConsumerState<TypingTestPanel> createState() => _TypingTestPanelState();
}

class _TypingTestPanelState extends ConsumerState<TypingTestPanel> {
  final _ctrl = TextEditingController();
  TypingTestSample? _activeSample;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _selectSample(TypingTestSample s) {
    setState(() => _activeSample = s);
    if (s.isCustomizable) {
      _showCustomRepeatDialog(s);
    } else {
      setState(() => _ctrl.text = s.text);
    }
  }

  Future<void> _showCustomRepeatDialog(TypingTestSample sample) async {
    const defaultLine = 'aaaaa00000℃℃℃℃℃哈哈哈哈哈~~~~~±×÷';
    int repeatCount = 50;
    final lineCtrl = TextEditingController(text: defaultLine);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final singleLine = lineCtrl.text.isEmpty ? defaultLine : lineCtrl.text;
          final totalChars = (singleLine.length + 1) * repeatCount;
          final estSeconds = (totalChars * 0.025).round();

          return AlertDialog(
            title: const Text('配置长文本稳定性测试'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '每行内容相同并以换行结尾，用于长文本稳定性排查。',
                    style: TextStyle(fontSize: 12.5, color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 14),
                  const Text('单行基准句子：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: lineCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('重复行数：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('$repeatCount 行', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [20, 50, 100, 200].map((c) {
                      final isSel = repeatCount == c;
                      return ChoiceChip(
                        label: Text('$c 行'),
                        selected: isSel,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setDialogState(() => repeatCount = c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '统计：$repeatCount 行 · 单行 ${singleLine.length} 字符 · 共 $totalChars 字符 (预估约 $estSeconds 秒)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final buffer = StringBuffer();
                  for (var i = 0; i < repeatCount; i++) {
                    buffer.write(singleLine);
                    if (i < repeatCount - 1) buffer.write('\n');
                  }
                  setState(() {
                    _ctrl.text = buffer.toString();
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('生成并填入'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text;
    if (text.trim().isEmpty) return;
    var ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) {
      final ok = await BleConnectManualSheet.show(context);
      if (!ok || !mounted) return;
      ble = ref.read(bleServiceProvider);
      if (!ble.isConnected) return;
    }
    if (!mounted) return;

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final rawFeedback = await settingsRepo.get('typing_done_feedback');
    final prefs = TypingDonePrefs.parse(rawFeedback);
    if (!mounted) return;

    // 唤起全局悬浮球与打字进度监控，支持实时查看进度和紧急停止 (Emergency Stop)
    final typingCtrl = ref.read(typingProgressControllerProvider);
    final sampleTitle = _activeSample?.label ?? '测试输入';
    typingCtrl.startTyping(
      title: '测试输入 · $sampleTitle',
      text: text,
    );

    showAppToast(context, '已加入发送队列（${text.length} 字符），可通过悬浮窗随时急停');
    final ok = await ble.sendTextDone(text);
    typingCtrl.finishTyping();

    if (!mounted) return;
    if (ok) {
      await notifyTypingDone(context, prefs);
    } else {
      showAppToast(context, '发送中断或失败，请检查连接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard_alt_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '测试输入',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                if (_ctrl.text.isNotEmpty)
                  Text(
                    '${_ctrl.text.length} 字符',
                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '点击预设载入测试内容，发送过程可通过全局悬浮窗实时监控与紧急停止。',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: kTypingTestSamples.map((s) {
                final isSelected = _activeSample?.label == s.label;
                return ChoiceChip(
                  label: Text(s.label),
                  selected: isSelected,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _selectSample(s),
                );
              }).toList(),
            ),

            if (_activeSample != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _activeSample!.description,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            TextField(
              controller: _ctrl,
              minLines: 3,
              maxLines: 7,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '选择上方测试预设，或直接粘贴待测文本……',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_ctrl.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _ctrl.clear();
                      _activeSample = null;
                    }),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('清空', style: TextStyle(fontSize: 12)),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('发送测试'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
