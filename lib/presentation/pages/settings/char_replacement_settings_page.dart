import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/character_sanitizer.dart';

/// 非法/特殊字符转换规则管理页面 (/settings/char-replacement)
class CharReplacementSettingsPage extends ConsumerWidget {
  const CharReplacementSettingsPage({super.key});

  Future<void> _showAddOrEditDialog(BuildContext context, WidgetRef ref, [String? initialFrom, String? initialTo]) async {
    final fromCtrl = TextEditingController(text: initialFrom ?? '');
    final toCtrl = TextEditingController(text: initialTo ?? '');

    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(initialFrom == null ? '添加替换规则' : '编辑替换规则'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fromCtrl,
                decoration: const InputDecoration(
                  labelText: '特殊/不支持字符 (原字符)',
                  hintText: '例如: ℉, •, ®',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: toCtrl,
                decoration: const InputDecoration(
                  labelText: '替换为安全字符 (目标字符)',
                  hintText: '例如: 度F, ·, (R)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final from = fromCtrl.text;
                final to = toCtrl.text;
                if (from.isNotEmpty) {
                  ref.read(charReplacementRulesProvider.notifier).saveRule(from, to);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        fromCtrl.dispose();
        toCtrl.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(charReplacementRulesProvider);
    final sortedKeys = rules.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('字符替换'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: '恢复默认预设',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('恢复默认转换规则'),
                  content: const Text('确定要将所有字符替换规则重置为系统默认配置吗？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('恢复')),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(charReplacementRulesProvider.notifier).resetToDefaults();
                if (context.mounted) {
                  showAppToast(context, '已恢复默认转换规则');
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.amber.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当文书中包含蓝牙键盘硬件无法打出的特殊符号时，系统将在审阅页高亮并在发送前提供一键忠实转换。',
                    style: TextStyle(fontSize: 12, color: Colors.brown.shade800, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: sortedKeys.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final from = sortedKeys[i];
                final to = rules[from] ?? '';

                return ListTile(
                  dense: true,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          from,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          to.isEmpty ? '(清空删除)' : to,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: to.isEmpty ? Colors.grey : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showAddOrEditDialog(context, ref, from, to),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                        onPressed: () => ref.read(charReplacementRulesProvider.notifier).deleteRule(from),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('添加规则'),
        onPressed: () => _showAddOrEditDialog(context, ref),
      ),
    );
  }
}
